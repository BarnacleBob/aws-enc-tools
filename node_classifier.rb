#!/usr/bin/ruby

require 'json'
require 'logger'
require 'pathname'
require 'yaml'

log=Logger.new(STDOUT)
log.level=Logger::ERROR

CACHE_FILE='/var/lib/puppet/ec2/instance_cache.yaml'
CACHE_UPDATER=File.dirname(__FILE__) + '/ec2_instance_list_cache.rb'

if File.stat(CACHE_FILE).uid != Process.uid
	abort 'please run this as the same user as puppetmaster runs'
end

if ARGV.length < 0
	abort 'please pass an instance-id to classify'
end

instance_id = ARGV[0]

if not instance_id =~ /^i-[a-zA-Z0-9]+$/
	abort "#{instance_id} does not look like a ec2 instance id"
end

if not File.exists?(CACHE_FILE)
	`#{CACHE_UPDATER}`
end

instances=YAML.load( IO.read( CACHE_FILE ) )

if instances.empty?
	abort 'failed to load instances from cache file'
end

if not instances.has_key?(instance_id)
	abort "could not find instance with id #{instance_id} in yaml cache"
end

instance = instances[instance_id]

if not instance['Tags'].has_key?('puppet_role')
	abort "instance with id #{instance_id} found but has no puppet_role tag"
end

role = instance['Tags']['puppet_role']
node_config={
	'classes'=> {'role::' + role => nil},
	'params' => nil
}
	
puts YAML.dump(node_config)
