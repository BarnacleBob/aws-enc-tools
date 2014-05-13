#!/usr/bin/ruby

require 'open-uri'
require 'logger'
require 'json'
require 'yaml'
require 'timeout'

class Ec2Instances
	def initialize(timeout=300)
		@log = Logger.new(STDERR)
		@log.level = Logger::ERROR
		
		@log.info('Ec2Instances cache starting up')

		@cache_dir = '/var/lib/puppet/ec2'
		@cache_file = @cache_dir + '/instance_cache.yaml'
		@cache_timeout = timeout
		load_cache()
	end

	def method_missing(name, *args, &block)
		@instances.send(name, *args, &block)
	end
	
	def load_cache()
		@log.info("loading cache")
		if not File.exists?(@cache_file) or get_file_age(@cache_file) > @cache_timeout
			update_cache()
		end
		@instances=YAML.load( IO.read( @cache_file ) )
	end

	def check_make_cache_dir
		Dir.mkdir(@cache_dir) unless File.exists?(@cache_dir)
	end

	def metadata_fetch(item)
		uri_data = nil
		begin
			status = Timeout::timeout(2) do
				@log.info("fetching meatadata item #{item}")
				uri_data = open("http://169.254.169.254/latest/meta-data/" + item).read()
				@log.info("fetched #{uri_data}")
			end
		rescue Exception => e
			@log.error("metadata_fetch caught error #{e.to_s}")
			return nil
		end
		return uri_data
	end

	def get_file_age(file)
		return Time.now - File.mtime(file)
	end

	def ec2(region, command)
		@log.info("calling ec2 command #{command}")
		ec2_command_out=`/usr/local/bin/aws --region=#{region} ec2 #{command}`
		if $?.to_i !=0 or ec2_command_out.empty?
			@log.error('aws api command failed')
			return nil
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

	def update_cache
		@log.info("updating #{@cache_file}")
		primary_mac_address = metadata_fetch('network/interfaces/macs/').split('\n')[0]
		vpc_id = metadata_fetch("network/interfaces/macs/#{primary_mac_address}/vpc-id")
		zone = metadata_fetch('placement/availability-zone')
		
		if not primary_mac_address or not vpc_id or not zone
			return nil
		end
		
		region = zone[0..-2]
	
		instances = {}
	
		response_json = ec2(region, "describe-instances --filters 'Name=vpc-id,Values=#{vpc_id}'")
		if not response_json
			return nil
		end
		response=JSON.parse( response_json )
	
		response["Reservations"].each do |reservation|
			reservation["Instances"].each do |instance|
				@log.info("Found instance " + instance["InstanceId"])
				colapse_ec2_tags(instance)
				instances[instance["InstanceId"]]=instance
			end
		end
	 
	 	@log.info("writing cache file #{@cache_file}.tmp")
		File.new(@cache_file + '.tmp', 'w').write(YAML.dump(instances))
	 	@log.info("moving cache file #{@cache_file}.tmp to #{@cache_file}")
		File.rename(@cache_file + '.tmp', @cache_file)
	end
end
