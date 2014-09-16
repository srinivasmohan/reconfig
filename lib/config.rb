#!/usr/bin/env ruby

require "etcd"
require "resolv"
require "json"
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "utils.rb"
require "worker.rb"

include Reconfig::Utils

module Reconfig
  CfgDir="/etc/reconfig" 
  
  class Options
    include Mixlib::CLI
    option :help, :short =>'-h', :long => '--help', :boolean => true, :default => false, :description => "Show this Help message.", :show_options => true, :exit => 0
    option :host, :long => "--host ETCDHOST", :default => "127.0.0.1", :description => "Etcd host to connect to. Default: 127.0.0.1"
    option :port, :long => "--port PORT", :default => 4001, :description => "Etc port. Default: 4001"
    option :prefix, :short => "-p someprefix", :long => "--prefix someprefix", :default => nil, :description => "Key prefix to use. Must begin with '/'. Default: empty"
    option :debug, :short => "-d", :long => "--debug", :boolean => true, :default => false, :description => "Enable debug mode."
    option :onetime, :short => "-o", :long => "--onetime", :boolean => true, :default => false, :description => "Run onetime and exit"
    option :notreally, :short => "-n", :long => "--notreally", :boolean => true, :default => false, :description => "Display changes but do not modify target files. Default: false" 
    option :ssl, :short =>"-s", :long => "--ssl", :boolean => true, :default => false, :description => "Use SSL mode"
    option :ssl_cafile, :long => "--ssl_cafile PATH-TO-CA-FILE", :default => nil, :description => "Path to SSL CA (cert auth) file"
    option :ssl_cert , :long => "--ssl_cert PATH-TO-SSL-CERT", :default => nil, :description => "Path to SSL cert"
    option :ssl_key, :long => "--ssl_key PATH-TO-SSL-KEY", :default => nil, :description => "Path to SSL Key"
    option :ssl_passphrase, :long => "--ssl_passphrase Passphrase", :default => nil, :description => "Passphrase if SSL Key is encrypted"
    option :cfgdir , :short => "-c CFGDIR", :long => "--cfgdir CFGDIR", :default => CfgDir, :description => "Toplevel config dir. Defaults to #{CfgDir}"
    option :srv, :long => "--srv SRV-RECORD", :default => nil, :description => "Use DNS SRV record to locate the etcd host/port. If specified, overrides host/port"
    option :version, :long => "--version", :boolean => true, :default => false, :description => "Display version and exit."
 end #end of Options

  class Config

    attr_reader :cfgdir, :configs, :confdir, :templatedir, :targets, :host, :port
    attr_accessor :debug

    def initialize(opts={})
			@cfgdir=opts[:cfgdir]
			@debug=opts[:debug] ? opts[:debug] : false
      @confdir=@cfgdir +"/conf.d"
      @templatedir=@cfgdir+"/templates"
      @prefix=opts[:prefix] || nil #Will be prefixed to etcd keys to watch for.
			dirs=[@cfgdir, @confdir, @templatedir]
      logmsg("Starting with ConfigDir=#{@cfgdir} Debug=#{@debug}" + (@prefix.nil? ? "": " Prefix=#{@prefix}"))
			abort "Missing config dirs #{dirs.join(" ")}" unless checkdirs(dirs)
      @configs=Hash.new
      @targets=Hash.new
      cfgs=[]
      locatecfgs.each do |thiscfg|
        c=parsecfg(thiscfg)
       	logmsg("Could not process #{thiscfg} - #{c[:err]}") if c[:err]
        cfgs << c[:obj] if c[:obj] 
      end
      validateCfg(cfgs) #populate @configs
      $stderr.puts "ConfigHash: "+JSON.pretty_generate(@configs) if @debug
      if @configs.keys.length>0
        logmsg("Targeting config files: "+@targets.keys.sort.join(" "))
      else
        logmsg("No valid configs to work with!")
      end
      @srv=opts[:srv].nil? ? nil : opts[:srv] 
      @host=opts[:host]
      @port=opts[:port]
      #If provided a DNS SRV record, then use that to locate a valid host:port combo for etcd.
			@connectparams={}
      @connectparams.merge!({
        :use_ssl => opts[:ssl],
        :ca_file => opts[:ssl_cafile],
        :ssl_cert => opts[:ssl_cert],
        :ssl_key => opts[:ssl_key],
        :passphrase => opts[:ssl_passphrase]
      }) if opts[:ssl]
    end

    def checkdirs(dirs=Array.new)
     y=true
     dirs.each { |x| y&&=File.directory?(x) }
     y
    end

		def parsecfg(f=nil)
      return {:err => "Nil config"} if f.nil?
      return {:err => "Missing config file"} unless File.exists?(f)
     	begin
       obj=JSON.parse(File.read(f))
       obj.merge!({"id" => f}) unless obj.has_key?("id")
       return {:obj => obj}
      rescue Exception => e
       logmsg("Error reading #{f} - #{e.inspect}")
       return {:err => e.inspect }
      end 
		end

    def validateCfg(cfgs=Array.new)
      return [] unless cfgs.is_a?(Array)
      #cfg is an array of hashes, each to have:
      #We expect hash to have 
      # key => etcd key to watch
      # target => Target config
      # source => Source template. this will be sourced from @templatedir
      # id (optional)
      cfgnew=Hash.new
      cfgs.each do |t|
        if !checkobj(t)
          logmsg("Ignoring #{t["id"]} - This must have keys: source,target,key. Source(file) must exist in #{@templatedir} and Key must start with a /")
          next
        end 
      end
      cfgnew
    end

    def checkobj(h=Hash.new)
      return false unless h.is_a?(Hash)
      %w{source target key}.each {|x| return false unless h.has_key?(x)}
      return false unless File.exists?(@templatedir+"/"+h["source"])
      return false unless h["key"]=~/^\//
			if @targets.has_key?(h["target"])
				logmsg("Ignoring #{h["id"]} since it REPEATS target config #{h["target"]}")
				return false
			end
      h["source"]=@templatedir + "/" + h["source"]
      h["key"]=@prefix + h["key"] unless @prefix.nil?
      h["key"].squeeze!("/")
      if @configs.has_key?( h["key"] )
        logmsg("Ignoring #{h["id"]} since Etcd Key #{h["key"]} is already bound to item #{@configs[h["key"]]["id"]}")
        return false
      end
      h["recursive"]=h.has_key?("recursive") && h["recursive"] ? true : false
      h["checkcmd"]=h.has_key?("checkcmd") ? h["checkcmd"] : nil
      h["reloadcmd"]=h.has_key?("reloadcmd") ? h["reloadcmd"] : nil
      @configs[ h["key"] ] = h
			@targets[h["target"]]=h["id"]
      desc=h["recursive"] ? "TREE" : "LEAF"
      logmsg("TargetConfig #{h["target"]} bound to Key:#{h["key"]} (#{desc}) Template:#{h["source"]}") if @debug
      return true 
    end

	  def locatecfgs
      Dir.glob("#{@confdir}/*.json").sort.map { |f| File.expand_path(f)}
    end

    #Given a SRV type record, locate the host:port combination (pick one of many)
    def getHostInfo
      return [nil,nil] if @srv.nil?
      resolver=Resolv::DNS.new
      all=resolver.getresources(srvname,Resolv::DNS::Resource::IN::SRV)
      return [nil,nil] if all.length==0
      rec=all[(rand(all.length)+1).to_i-1]
      return [ rec.target.to_s, rec.port.to_i ]
    end

    #Return an etcd client. Wont know if you can connect till you connect.
    def client
      client=nil
      chash={:host => @host, :port => @port }
			unless @srv.nil?
        chash[:host], chash[:port] = getHostInfo
        abort "Etcd host/port was null from SRV record #{@srv}!"
        logmsg("Etcd host #{chash[:host]}:#{chash[:port]} from SRV #{@srv}") if @debug
      end
      chash.merge!(@connectparams)		 
      if chash[:use_ssl]
        #cafile/cert/key is provided MUST exist.
        pp=chash[:passphrase]; chash.delete(:passphrase)
       	client=Etcd.client host: chash[:host], port: chash[:port] do |clt|
          clt.use_ssl = true
          clt.ca_file = chash[:ca_file]
          clt.ssl_cert = chash[:ssl_cert].nil? ? nil: OpenSSL::X509::Certificate.new(File.read(chash[:ssl_cert])) 
          clt.ssl_key = chash[:ssl_key].nil? ? nil: OpenSSL::PKey::RSA.new(File.read(chash[:ssl_key]), pp) 
        end 
      else
       client=Etcd.client(chash)
      end
      return client	
    end

    def debug!
      @debug=!@debug
      logmsg("Debug toggled to #{@debug}") 
    end

  end #end of Config class

  class Reactor

  end
end #end of module
