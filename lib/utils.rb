#!/usr/bin/env ruby

require "etcd"
require "resolv"
require "json"

module Reconfig
  Timeformat='%Y%m%d.%H:%M:%S'
  CfgDir=ENV['CFGDIR'] || "/etc/reconfig"
 
  module Utils  
    def logmsg(msg=nil)
      $stderr.puts "#{Time.now.strftime(Timeformat)} [PID #{$$.to_i}] - #{msg}" unless msg.nil?
    end

  end

  class Config

    attr_reader :cfgdir, :configs, :confdir, :templatedir
    attr_accessor :debug

    def initialize(opts={})
			@cfgdir=CfgDir
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
     	puts "Before: "+JSON.pretty_generate(@configs)
      @configs=validatecfg(@configs)
      puts "After: "+JSON.pretty_generate(@configs)
      logmsg("No valid configs to work with!") unless @configs.length> 0
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
        cfgnew << t            
      end
      cfgnew
    end

    def checkobj(h=Hash.new)
      return false unless h.is_a?(Hash)
      %w{source target key}.each {|x| return false unless h.has_key?(x)}
      return false unless File.exists?(@templatedir+"/"+h["source"])
      return false unless h["key"]=~/^\//
      return true 
    end

	  def locatecfgs
      Dir.glob("#{@confdir}/*.json").sort.map { |f| File.expand_path(f)}
    end

  end
end
