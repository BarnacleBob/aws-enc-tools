#!/usr/bin/ruby

require 'logger'

require File.dirname(__FILE__) + '/script_utils.rb'

SETUP_SCRIPT = File.dirname(__FILE__) + '/bootstrapclient.sh'

$utils = Utils.instance
$utils.runas('puppet')
if ARGV[1]=='infolog'
	$utils.log.level = Logger::INFO
end

if ARGV.length < 1
	abort "must pass instance id to setup"
end

instance_id = ARGV[0]

def Log (msg)
	$utils.log.info(msg)
	$utils.syslog.info(msg)
end
def GetInstanceName(instance)
	name_prefix = instance['Tags']['puppet_role']
	if instance['Tags'].has_key?('application')
		name_prefix = name_prefix + "-" + instance['Tags']['application'].split(',')[0]
	end
	if instance['Tags'].has_key?('app_environment')
		name_prefix = name_prefix + "-" + instance['Tags']['app_environment']
	end
	name_tag = $utils.get_next_friendly_name(name_prefix)
	return name_tag
end
def UpdateInstanceName(instance_id, name, suffix="")
	if suffix!=''
		name = "#{name}---#{suffix}"
	end
	$ec2_cli.cli("create-tags --resources #{instance_id} --tags Key=Name,Value=#{name}")
end

instances=Ec2Instances.new(timeout=60)

$ec2_cli = Ec2Cli.new()

Log("setting up for #{instance_id}")

if not instances.has_key?(instance_id)
	Log("could not find instance #{instance_id}")
	abort "could not find instance #{instance_id}"
end

instance = instances[instance_id]
instance_name = GetInstanceName(instance)
UpdateInstanceName(instance_id, instance_name, "setup")
instance_address = instance['PrivateIpAddress']
output=`#{SETUP_SCRIPT} #{instance_address} 2>&1`
result=$?

if result == 0
	Log("new_instance_setup completed #{instance_id} succesfully")
	UpdateInstanceName(instance_id, instance_name)
	status = "success"

	$ec2_cli.cli("delete-tags --resources #{instance_id} --tags Key=InSetup")
else
	Log("new_instance_setup completed #{instance_id} with failures")
	UpdateInstanceName(instance_id, instance_name, "failed")
	status = "failed"
end

$utils.email('adsynth-ops@threadbaregames.com', "#{instance_id} setup log: #{status}", output)
