#!/usr/bin/ruby
require "json"
require "etcd"
require 'mixlib/cli'
require "resolv"
$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "utils.rb"
require "cmdline.rb"
include Reconfig::Utils
include Reconfig::Cmdline

#Parse cmdline opts.
cli=Reconfig::Cmdline::EtcdUtilOpts.new
cli.parse_options
op = cli.config[:op].upcase
key = cli.config[:key]
value = cli.config[:value]

if !cli.config[:version]
	abort "Need operation and key!" if op.nil? || key.nil?
	abort "Need a key and value for a SET" if op=="SET" && value.nil?
end
client=etcdclient(cli.config)


$stderr.puts "Connected to [#{client.version}] with leader #{client.leader} and nodes #{client.machines}" if cli.config[:debug] || cli.config[:version]
exit if cli.config[:version]

case op
when 'GET'
	begin
		$stderr.puts "Running recursive find - May take a few secs..." if cli.config[:recursive]
		results=find(client,key,cli.config[:recursive])
		puts JSON.pretty_generate(results)
	rescue Etcd::KeyNotFound => ke
		$stderr.puts "Etcd::KeyNotFound #{key}"
	end

when 'SET'

	$stderr.puts "Setting #{key} to #{value} #{cli.config[:ttl].nil? ? nil: "TTL=#{cli.config[:ttl]}s"}"
	cli.config[:ttl].nil? ? client.set(key, value:	value) : client.set(key, value: value, ttl: cli.config[:ttl].to_i)

when 'DEL'
	$stderr.puts "Deleting #{key} Recursive=#{cli.config[:recursive]}" if cli.config[:debug]
	begin
		client.delete(key, recursive: cli.config[:recursive])
	rescue Exception => ke
		$stderr.puts "Etcd::KeyNotFound #{key} - #{ke.inspect}" if cli.config[:debug]
	end
when 'WATCH'
	$stderr.puts "Watching key #{key} for changes #{cli.config[:recursive] ? "Recursively." : ":"}"
	ret=client.watch(key, recursive: cli.config[:recursive])
	p ret
else
	$stderr.puts "No such option #{op}"
end

