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

INSTANCE_ID=$(/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/instance-id)
[ -z "$INSTANCE_ID" ] && { echo "could not fetch instance id from metadataservice"; exit 1; }

apt-get update
apt-get -y install git

# Check out the repo first in case that fails
echo "cloning puppet repo to test git connection"
git clone git@github.com:CranestyleLabs/PixelServerOps.git || { echo "failed to checkout repository"; exit 1; }

echo "checking for puppet labs apt repo"
if dpkg -l puppetlabs-release > /dev/null; then
	echo "already installed"
else
	echo "installing"
	wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb
	dpkg -i puppetlabs-release-precise.deb
	apt-get update
fi

apt-get -y purge puppetmaster puppetdb

apt-get -y install puppetmaster

echo "stopping puppet master"
service puppetmaster stop > /dev/null 2>&1

for dir in /etc/puppet /var/lib/puppet/ssl /etc/puppetdb; do
	echo "backing up ${dir}"
	mv -v ${dir} ${dir}.bootstrap-backup-$(date +%Y%m%d%H%M%S)
	mkdir -v ${dir}
done

mkdir /etc/puppetdb/conf.d
chown puppet:puppet /var/lib/puppet/ssl

# Check out the repo first in case that fails
cd /etc/puppet
echo "cloning puppet repo again in the correct location to work around a bug in git submodules"
git clone git@github.com:CranestyleLabs/PixelServerOps.git || { echo "failed to checkout repository"; exit 1; }
cd PixelServerOps
git submodule init
git submodule update
cd -
ln -s "/etc/puppet/${GITHUB_REPO_NAME}" "/etc/puppet/${REPO_ALIAS}"

echo "Creating temporary site.pp"
echo "stage{'apt': before => Stage['main']}" >> $TEMP_DIR/site.pp
echo "node \"$(hostname -f)\" {class{'role::puppetmaster': bootstrap => true }}" >> $TEMP_DIR/site.pp

echo "$(/usr/bin/facter ipaddress) $INSTANCE_ID" >> /etc/hosts

echo "Standing up temporary master"
/usr/bin/puppet master \
	--no-daemonize \
	--verbose \
	--masterport=8120 \
	--dns_alt_names="$(hostname -f),$INSTANCE_ID,$(facter ipaddress)" \
	--vardir=${TEMP_DIR}/puppet_tmp \
	--confdir=${TEMP_DIR}/puppet_etc \
	--modulepath=/etc/puppet/${REPO_ALIAS}/puppet/modules \
	--manifest=${TEMP_DIR}/site.pp \
	--autosign=true 2>&1 | tee ${TEMP_DIR}/master.log | perl -ple 's#^#puppetmaster: #' &


i=0
while [ "$i" -lt "120" ]; do
	grep -irl "Notice: Starting Puppet master version" ${TEMP_DIR}/master.log > /dev/null 2>&1
	RET=$?
	if [ "$RET" -eq "0" ]; then
		break
	fi
	sleep 1
	i=$(( $i + 1 ))
done

[ ! -e "/proc/${MASTER_PID}" ] && { echo "puppet master failed to start"; exit 1; }

/usr/bin/puppet agent \
	--test \
	--no-report \
	--masterport=8120 \
	--waitforcert=30 \
	--certname=$INSTANCE_ID \
	--server=$(facter ipaddress) \
	--confdir=${TEMP_DIR}/puppet_etc \
	--vardir=${TEMP_DIR}/puppet_tmp 2>&1 | perl -ple 's#^#puppetagent: #'

read -p "enter to continue.  ctrl-c to abort"

echo "Stopping temporary master"
kill $(cat ${TEMP_DIR}/puppet_tmp/run/master.pid)
sleep 4

service puppetmaster restart

sleep 4

echo "Doing regular puppet run"
echo "$(/usr/bin/facter ipaddress) $INSTANCE_ID" >> /etc/hosts
/usr/bin/puppet agent --test --certname=$INSTANCE_ID --server=$(facter ipaddress) --no-report

# Puppetdb takes forever to start:
i=0
while [ "$i" -lt "300" ]; do
	netstat -lpn  | grep -i ":8081" && break
	sleep 1
	i=$(( $i + 1 ))
done

echo "$(/usr/bin/facter ipaddress) $INSTANCE_ID" >> /etc/hosts
/usr/bin/puppet agent --test --certname=$INSTANCE_ID --server=$INSTANCE_ID

echo "Cleaning up temp"
rm -rf $TEMP_DIR
