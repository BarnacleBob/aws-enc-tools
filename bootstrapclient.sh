#!/bin/bash

ROOT_DIR=/etc/puppet/puppet_repo
ADDRESS=$1
NODECONFIG=$2

function list_nodeconfigs(){
	echo "valid nodeconfigs:"
	find $ROOT_DIR/node_classification/ -type f -name '*.yaml' -printf '%f\n' | cut -d. -f1
}

[ ! -e "$ROOT_DIR" ] && { echo "please run this from the puppet master"; exit 1; }

[ -z "$NODECONFIG" ] && { echo "usage: $(basename $0) (address|hostname) nodeconfig"; list_nodeconfigs; exit 1; }
[ ! -e "$ROOT_DIR/node_classification/$NODECONFIG.yaml" ] && { echo "invalid node config"; list_nodeconfigs; exit 1; }
[ -z "$SSH_AUTH_SOCK"  ] && { echo "Please make sure the ssh key to access the new machine is available in an agent"; exit 1; }
[ "$(cd $ROOT_DIR; git status --porcelain | grep -v '?' | wc -l)" -ne "0" ] && { echo "the git repo at $ROOT_DIR is in a strange state such as modified but uncommitted files"; exit 1; }



LOCAL_HOSTNAME=$(/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/local-hostname)
HOSTNAME=$(ssh ubuntu@$ADDRESS 'hostname -f')
[ -z "$HOSTNAME" ] && { echo "could not get hostname from ubuntu@$ADDRESS.  ssh problem?"; exit 1; }

ssh ubuntu@$ADDRESS 'wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb; sudo dpkg -i puppetlabs-release-precise.deb; sudo apt-get update; sudo apt-get install -y puppet'

INSTANCE_ID=$(ssh ubuntu@$ADDRESS '/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/instance-id')

cd $ROOT_DIR/node_classification
sudo ln -s $NODECONFIG.yaml $INSTANCE_ID.yaml
sudo git add $INSTANCE_ID.yaml
sudo git commit -m "bootstrapclient.sh adding $INSTANCE_ID as $NODECONFIG"
sudo -E git push -u origin master

ssh ubuntu@$ADDRESS "sudo puppet agent --test --waitforcert=30 --server=${LOCAL_HOSTNAME} --certname=${INSTANCE_ID}" &
RUN_PID=$!
sleep 15
sudo -E puppet cert sign ${INSTANCE_ID}

wait $RUN_PID
