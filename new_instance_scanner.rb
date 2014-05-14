#!/usr/bin/ruby

require 'logger'

require File.dirname(__FILE__) + '/script_utils.rb'

SETUP_SCRIPT = File.dirname(__FILE__) + '/bootstrapclient.sh'

utils = Utils.instance
if ARGV[0]=="infolog"
	utils.log.level = Logger::INFO
end

utils.runas('puppet')

lock = utils.lock_file('/var/lib/puppet/ec2/new_instance_scanner.lock')
if not lock
	abort("Could not get lock.  instance already running")
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

	if not instance["Tags"].has_key?('puppet_role')
		utils.error("Unsetup instance #{instance_id} does not have a puppet_role tag")
		next
	end
	
	utils.log.info("calling setup for #{instance_id}")
	instance_address = instance["PrivateIpAddress"]
	output=utils.cmd("#{SETUP_SCRIPT} #{instance_address}")
	
	utils.log.info(output)
	
	utils.log
end

utils.unlock_file(lock)
