#!/usr/bin/ruby

require 'logger'

require File.dirname(__FILE__) + '/script_utils.rb'

SETUP_SCRIPT = File.dirname(__FILE__) + '/new_instance_setup.rb'

utils = Utils.instance
if ARGV[0]=='infolog'
	utils.log.level = Logger::INFO
end

utils.runas('puppet')

lock = utils.lock_file('/var/lib/puppet/ec2/new_instance_scanner.lock')
if not lock
	abort('Could not get lock.  instance already running')
end

inventory_service = PuppetInventory.new()
puppet_nodes = inventory_service.nodes()
instances=Ec2Instances.new(timeout=60)

ec2_cli = Ec2Cli.new()

instances.each do |instance_id, instance|
	utils.log.info("checking instance #{instance_id}")

	if instance['State']['Name'] != 'running'
		utils.log.info("Skipping instance #{instance_id} with state " + instance['State']['Name'])
		next
	end
	
	if puppet_nodes.has_key?(instance_id)
		utils.log.info("instance #{instance_id} already in puppet inventory")
		next
	end

	if not instance['Tags'].has_key?('puppet_role')
		utils.error("Unsetup instance #{instance_id} does not have a puppet_role tag")
		next
	end
	
	if instance['Tags'].has_key?('InSetup')
		utils.log.info("instance #{instance_id} being setup already")
		next
	end
	
	utils.log.info("calling setup for #{instance_id}")
	utils.syslog.info("new_instance_scanner calling setup for #{instance_id}")
	pid = fork do
		exec "#{SETUP_SCRIPT} #{instance_id}"
	end
	Process.detach(pid)
	$ec2_cli.cli("create-tags --resources #{instance_id} --tags Key=InSetup,Value=true")
end

utils.unlock_file(lock)

