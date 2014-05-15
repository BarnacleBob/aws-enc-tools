#!/bin/bash

exec 2>&1

ADDRESS=$1
SSH_KEY='/var/lib/puppet/.ssh/PuppetMasterAutoConfigure.pem'
ssh="ssh -i $SSH_KEY -o StrictHostKeyChecking=no "

[ ! -r "$SSH_KEY" ] && { echo "$SSH_KEY cannot be found or read.  cannot continue"; exit 1; }

LOCAL_HOSTNAME=$(/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/local-hostname)
[ -z "$LOCAL_HOSTNAME" ] && { echo "Could not contact metadata service"; exit 1; }

# Clear host keys for this host
ssh-keygen -R $ADDRESS > /dev/null 2>&1

HOSTNAME=$($ssh ubuntu@$ADDRESS 'hostname -f')
[ -z "$HOSTNAME" ] && { echo "could not get hostname from ubuntu@$ADDRESS.  ssh problem?"; exit 1; }

$ssh ubuntu@$ADDRESS 'wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb'
$ssh ubuntu@$ADDRESS 'sudo dpkg -i puppetlabs-release-precise.deb; sudo apt-get update; sudo apt-get install -y puppet'

# Fix facter for vpc's
scp -i $SSH_KEY /usr/lib/ruby/vendor_ruby/facter/ec2.rb ubuntu@$ADDRESS:ec2.rb
$ssh ubuntu@$ADDRESS 'sudo mv ec2.rb /usr/lib/ruby/vendor_ruby/facter/ec2.rb'

INSTANCE_ID=$($ssh ubuntu@$ADDRESS '/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/instance-id')

SERVER_INSTANCE_ID=$(/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/instance-id)
SERVER_IP=$(facter ipaddress)

$ssh ubuntu@$ADDRESS "sudo bash -c 'echo $SERVER_IP\ $SERVER_INSTANCE_ID >> /etc/hosts'"

$ssh ubuntu@$ADDRESS "sudo puppet agent --test --waitforcert=30 --server=${SERVER_INSTANCE_ID} --certname=${INSTANCE_ID}" &
RUN_PID=$!
sleep 15

puppet cert --config=/etc/puppet/puppet.conf sign ${INSTANCE_ID}

wait $RUN_PID

PUPPET_EXIT=$?

if [ "$PUPPET_EXIT" -eq "2" ]; then
	exit 0
fi

exit $PUPPET_EXIT
