#!/usr/bin/ruby

require 'logger'
require 'yaml'

require File.dirname(__FILE__) + '/script_utils.rb'

utils = Utils.instance 
utils.runas('puppet')

if ARGV.length < 1
	abort 'please pass an instance-id to classify'
end

instance_id = ARGV[0]

if ARGV[1]=="infolog"
	utils.log.level = Logger::INFO
end
    
if not instance_id =~ /^i-[a-zA-Z0-9]+$/
	abort "#{instance_id} does not look like a ec2 instance id"
end

instances=Ec2Instances.new()

if not instances.has_key?(instance_id)
	abort "could not find instance with id #{instance_id} in yaml cache"
end

instance = instances[instance_id]

if not instance['Tags'].has_key?('puppet_role')
	abort "instance with id #{instance_id} found but has no puppet_role tag"
end

role = instance['Tags']['puppet_role']
params = nil
if instance['Tags']['Name'] =~ /[a-zA-Z0-9\-_]+/
	utils.log.info("Found friendly name #{instance['Tags']['Name']}")
	params = { 'friendly_hostname' => instance['Tags']['Name'] }
end

node_config={
	'classes'=> {'role::' + role => nil},
	'params' => params
}
	
puts YAML.dump(node_config)

