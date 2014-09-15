#!/usr/bin/env ruby

require "etcd"
require "resolv"
require "json"

module Reconfig
  Timeformat='%Y%m%d.%H:%M:%S'
  CfgDir="/etc/reconfig" 
  module Utils  
    def logmsg(msg=nil)
      $stderr.puts "#{Time.now.strftime(Timeformat)} [PID #{$$.to_i}] - #{msg}" unless msg.nil?
    end

  end

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
 end

  class Config

    attr_reader :cfgdir, :configs, :confdir, :templatedir, :client
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
      @configs=Array.new 
      @targets=Hash.new
      locatecfgs.each do |thiscfg|
        c=parsecfg(thiscfg)
       	logmsg("Could not process #{thiscfg} - #{c[:err]}") if c[:err]
        @configs << c[:obj] if c[:obj]
      end
      @configs=validatecfg(@configs)
      puts "After: "+JSON.pretty_generate(@configs) if @debug
      if @configs.length>0
        logmsg("Targeting config files: "+@targets.keys.sort.join(" "))
      else
        logmsg("No valid configs to work with!")
      end
      #If provided a DNS SRV record, then use that to locate a valid host:port combo for etcd.
      if !opts[:srv].nil?
        opts[:host], opts[:port] = getHostInfo(opts[:srv])
        if opts[:host].nil? || opts[:port].nil?
          abort "Could not locate ETCD host/port from SRV record #{opts[:srv]}!"
        end
        logmsg("Will use etcd on #{opts[:host]}:#{opts[:port]} in #{opts[:ssl] ? "SSL": "HTTP"} mode (from SRV record)") if @debug
        opts[:port]=opts[:port].to_i
      end
      @client=nil
			@connectparams={ :host => opts[:host], :port => opts[:port].to_i }
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

    def validatecfg(cfgs=Array.new)
      return [] unless cfgs.is_a?(Array)
      #cfg is an array of hashes, each to have:
      #We expect hash to have 
      # key => etcd key to watch
      # target => Target config
      # source => Source template. this will be sourced from @templatedir
      # id (optional)
      cfgnew=[]
      cfgs.each do |t|
        if !checkobj(t)
          logmsg("Ignoring #{t["id"]} - This must have keys: source,target,key. Source(file) must exist in #{@templatedir} and Key must start with a /")
          next
        end 
        t["key"]=@prefix+t["key"] unless @prefix.nil?
				logmsg("Target #{t["target"]} bound to template:#{t["source"]}, key #{t["key"]}") if @debug
        cfgnew << t            
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
			@targets[h["target"]]=h["id"]
      return true 
    end

	  def locatecfgs
      Dir.glob("#{@confdir}/*.json").sort.map { |f| File.expand_path(f)}
    end

    #Given a SRV type record, locate the host:port combination (pick one of many)
    def getHostInfo(srvname=nil)
      return [nil,nil] if srvname.nil? || srvname.empty?
      resolver=Resolv::DNS.new
      all=resolver.getresources(srvname,Resolv::DNS::Resource::IN::SRV)
      return [nil,nil] if all.length==0
      rec=all[(rand(all.length)+1).to_i-1]
      return [ rec.target.to_s, rec.port ]
    end

    #Connect to etcd
    def connect
      if @connectparams[:use_ssl]
        #cafile/cert/key is provided MUST exist.
        pp=@connectparams[:passphrase]; @connectparams.delete(:passphrase)
       	@client=Etcd.client host: @connectparams[:host], port: @connectparams[:port] do |clt|
          clt.use_ssl = true
          clt.ca_file = @connectparams[:ca_file]
          clt.ssl_cert = @connectparams[:ssl_cert].nil? ? nil: OpenSSL::X509::Certificate.new(File.read(@connectparams[:ssl_cert])) 
          clt.ssl_key = @connectparams[:ssl_key].nil? ? nil: OpenSSL::PKey::RSA.new(File.read(@connectparams[:ssl_key]), pp) 
        end 

      else
       @client=Etcd.client(@connectparams)
      end
      begin
			  v=@client.version
        ldr=@client.leader
        logmsg("Connected to ETCD #{v} (Leader #{ldr}) successfully.")
      rescue Exception => e
        logmsg("Connection error #{@connectparams[:host]}:#{@connectparams[:port]}: #{e.inspect}")
        abort "Could not connect to ETCD #{@connectparams[:host]}:#{@connectparams[:port]}!"
      end
    	
    end

  end #end of Config class

end #end of module
