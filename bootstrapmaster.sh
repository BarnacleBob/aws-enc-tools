#!/bin/bash

GITHUB_REPO="git@github.com:CranestyleLabs/PixelServerOps.git"
GITHUB_REPO_NAME="PixelServerOps"
REPO_ALIAS="puppet_repo"

####################

[ "$EUID" -ne "0" ] && { echo "please run as root"; exit 1; }
[ -z "$SSH_AUTH_SOCK" ] && { echo "please launch an ssh agent, and load your github key before running"; exit 1; } 

####################

echo "WARNING THIS WILL RESET THE PUPPETMASTER CERTIFICATE AUTHORITY"
read -p "enter to continue.  ctrl-c to abort"

echo "Make sure you have read access to the github repo and that the address is ${GITHUB_REPO}"
read -p "enter to continue. ctrl-c to abort"

####################

# Make us a temp dir
TEMP_DIR=$(mktemp -d /tmp/puppet_boot_strap.XXXXXXX)
chmod 755 $TEMP_DIR
cd $TEMP_DIR
mkdir puppet_tmp
mkdir puppet_etc
echo "Made temp dir $TEMP_DIR"

# Check out the repo first in case that fails
echo "cloning puppet repo"
git clone git@github.com:CranestyleLabs/PixelServerOps.git || { echo "failed to checkout repository"; exit 1; }

echo "checking for puppet install"
if dpkg -l puppetmaster > /dev/null; then
	echo "already installed"
else
	echo "installing"
	apt-get -y install puppetmaster
fi

echo "stopping puppet master"
service puppetmaster stop > /dev/null 2>&1

for dir in /etc/puppet /var/lib/puppet/ssl; do
	echo "backing up ${dir}"
	mv -v ${dir} ${dir}.bootstrap-backup-$(date +%Y%m%d%H%M%S)
	mkdir -v ${dir}
done

echo "moving puppet repo to /etc/puppet"
mv -v "${GITHUB_REPO_NAME}" /etc/puppet
ln -s "/etc/puppet/${GITHUB_REPO_NAME}" "/etc/puppet/${REPO_ALIAS}"

echo "Creating temporary site.pp"
echo "node \"$(hostname -f)\" {class{'base': is_puppet_master=>true, puppet_master_address=>'$(hostname -f)'}}" >> $TEMP_DIR/site.pp

echo "Standing up temporary master"
/usr/bin/puppet master \
	--no-daemonize \
	--verbose \
	--masterport=8120 \
	--dns_alt_names=$(hostname -f) \
	--vardir=${TEMP_DIR}/puppet_tmp \
	--confdir=${TEMP_DIR}/puppet_etc \
	--modulepath=/etc/puppet/${REPO_ALIAS}/puppet/modules \
	--manifest=${TEMP_DIR}/site.pp \
	--autosign=true | perl -ple 's#^#puppetmaster: #' &


sleep 4
[ ! -e "/proc/${MASTER_PID}" ] && { echo "puppet master failed to start"; exit 1; }

read -p "enter to continue.  ctrl-c to abort"
/usr/bin/puppet agent \
	--test \
	--masterport=8120 \
	--server=$(hostname -f) \
	--confdir=${TEMP_DIR}/puppet_etc \
	--vardir=${TEMP_DIR}/puppet_tmp | perl -ple 's#^#puppetagent: #'
read -p "enter to continue.  ctrl-c to abort"

echo "Stopping temporary master"
kill $(cat ${TEMP_DIR}/puppet_tmp/run/master.pid)
sleep 4

echo "Doing regular puppet run"
/etc/puppet/puppetrun

echo "Cleaning up temp"
rm -rf $TEMP_DIR
