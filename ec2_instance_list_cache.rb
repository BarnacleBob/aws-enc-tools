#!/usr/bin/ruby

require 'open-uri'
require 'logger'
require 'json'
require 'yaml'

@log=Logger.new(STDERR)
@log.level=Logger::ERROR

CACHE_DIR='/var/lib/puppet/ec2'
CACHE_FILE=CACHE_DIR + '/instance_cache.yaml'
CACHE_TIMEOUT=300

Dir.mkdir(CACHE_DIR) unless File.exists?(CACHE_DIR)

def metadata_fetch(item)
	return open("http://169.254.169.254/latest/meta-data/" + item).read()
end

def get_file_age(file)
	return Time.now - File.mtime(file)
end 

def ec2(region, command)
	ec2_command_out=`/usr/local/bin/aws --region=#{region} ec2 #{command}`
	if $?.to_i !=0 or ec2_command_out.empty?
		@log.error('aws api command failed')
		exit
	end
	return ec2_command_out
end

def colapse_ec2_tags(instance)
	instance["RawTags"] = instance["Tags"]
	tags = {}
	instance["Tags"].each do |tag|
		tags[ tag["Key"] ] = tag["Value"]
	end
	instance["Tags"] = tags
end

if not File.exists?(CACHE_FILE) or get_file_age(CACHE_FILE) > CACHE_TIMEOUT or ARGV[0]=="expire"
	@log.info("updating $CACHE_FILE")
	primary_mac_address = metadata_fetch('network/interfaces/macs/').split('\n')[0]
	vpc_id = metadata_fetch("network/interfaces/macs/#{primary_mac_address}/vpc-id")
	zone = metadata_fetch('placement/availability-zone')
	region = zone[0..-2]
	
	instances = {}
	
	response=JSON.parse( ec2(region, "describe-instances --filters 'Name=vpc-id,Values=#{vpc_id}'") )
	
	response["Reservations"].each do |reservation|
		reservation["Instances"].each do |instance|
			colapse_ec2_tags(instance)
			instances[instance["InstanceId"]]=instance
		end
	end
	 
	if instances.empty?
		abort "failed to find any instances.  i should at least find me"
	end
	
	File.new(CACHE_FILE + '.tmp', 'w').write(YAML.dump(instances))
	File.rename(CACHE_FILE + '.tmp', CACHE_FILE)
end
