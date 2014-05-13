#!/usr/bin/ruby

require 'open-uri'
require 'json'
require 'yaml'
require 'etc'

require File.dirname(__FILE__) + '/script_utils.rb'

SETUP_SCRIPT = File.dirname(__FILE__) + '/bootstrapclient.sh'

if Etc.getpwuid(Process.uid).name != 'puppet'
	abort 'please run this as puppet'
end

inventory_service = PuppetInventory.new()
puppet_nodes = inventory_service.nodes()
instances=Ec2Instances.new(timeout=60)

ec2_cli = Ec2Cli.new()
utils = Utils.new()

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
