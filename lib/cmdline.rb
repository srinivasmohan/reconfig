#!/usr/bin/env ruby
require "etcd"
require "resolv"
require "json"
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "utils.rb"
include Reconfig::Utils

module Reconfig
  module Cmdline
    class EtcdUtilOpts
      include Mixlib::CLI
      option :op, :short => "-o OPERATION", :long => "--operation OPERATION", :default => "GET", :description => "Can be GET/SET/DEL - Defaults to GET"
      option :key, :short => "-k KEY", :long => "--key KEY", :default => nil, :description => "Key to work on. Required!"
      option :ttl, :short => "-t TTL", :long => "--ttl TTL", :default => nil, :description => "TTL in seconds. Matters only for SET"
      option :value, :short => "-v VAL",:long => "--value VAL", :description => "Value for the key. Required on SET"
      option :recursive, :short => "-r", :long => "--recursive", :boolean => true, :default => false, :description => "Recursive mode. False by default. Matters for DEL"
      option :help, :short =>'-h', :long => '--help', :boolean => true, :default => false, :description => "Show this Help message.", :show_options => true, :exit => 0
      option :debug, :short => "-d", :long => "--debug", :boolean => true, :default => false, :description => "Debug mode"
      option :host, :long => "--host HOST", :default => "127.0.0.1", :description => "Etcd host to connect to"
      option :port, :long => "--port PORT", :default => 4001, :description => "Etcd port"
      option :ssl, :short =>"-s", :long => "--ssl", :boolean => true, :default => false, :description => "Use SSL mode"
      option :ssl_cafile, :long => "--ssl_cafile PATH-TO-CA-FILE", :default => nil, :description => "Path to SSL CA (cert auth) file"
      option :ssl_cert , :long => "--ssl_cert PATH-TO-SSL-CERT", :default => nil, :description => "Path to SSL cert"
      option :ssl_key, :long => "--ssl_key PATH-TO-SSL-KEY", :default => nil, :description => "Path to SSL Key"
      option :ssl_passphrase, :long => "--ssl_passphrase SSL-Keys-Passphrase", :default => nil, :description => "Passphrase if SSL Key is encrypted"
      option :version, :long => "--version", :boolean => true, :default => false, :description => "Connect to etcd and dump version/leader info etc"
      option :srv, :long => "--srv SRV-RECORD", :default => nil, :description => "Use DNS SRV record to locate the etcd host/port. If specified, overrides host/port"
    end #End of class.


    #In recursive mode, return a hash. else array.
    def find(clt=nil,key=k,recursive=false)
	    return {} if clt.nil? || key.nil?
	    rethash=Hash.new
	    obj=recursive ? clt.get(key, recursive: recursive) : clt.get(key)
	    if obj.node.dir
		    childkeys=obj.children.map {|x| x.key }
		    if !recursive
			    return childkeys
		    else
			    childkeys.each do |x|
				    rethash.merge!(find(clt,x,recursive))
			    end
		    end
	    else
		    rethash[key]=obj.value
		    #puts "#{key} #{obj.value}"
	    end
	    rethash
    end


  end #End of module
end
