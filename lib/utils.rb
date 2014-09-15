#!/usr/bin/env ruby

require "etcd"
require "resolv"
require "json"

module Reconfig
  Timeformat='%Y%m%d.%H:%M:%S'
  CfgDir=ENV['CFGDIR'] || "/etc/reconfig"
  Debug=ENV['DEBUG'] ? true : false 
 
  module Utils  
    def logmsg(msg=nil)
      $stderr.puts "#{Time.now.strftime(Timeformat)} [PID #{$$.to_i}] - #{msg}" unless msg.nil?
    end

  end

  class Config

    attr_reader :mode, :cfgdir, :configs, :confdir, :templatedir
    attr_accessor :debug

    def initialize(mode=CfgDir,debug=Debug)
			@cfgdir=CfgDir
			@debug=debug
      @mode=mode
      @confdir=@cfgdir +"/conf.d"
      @templatedir=@cfgdir+"/templates"
			dirs=[@cfgdir, @confdir, @templatedir]
      logmsg("Starting with ConfigDir=#{@cfgdir} CfgDir=#{@mode} Debug=#{@debug}")
			abort "Missing config dirs #{dirs.join(" ")}" unless checkdirs(dirs)
      @configs=Array.new 
      locatecfgs.each do |thiscfg|
        c=parsecfg(thiscfg)
       	logmsg("Could not process #{thiscfg} - #{c[:err]}") if c[:err]
        @configs << c[:obj] if c[:obj]
      end

      p @configs
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
       return {:obj => obj}
      rescue Exception => e
       logmsg("Error reading #{f} - #{e.inspect}")
       return {:err => e.inspect }
      end 
		end

    def validatecfg(cfg=Hash.new)
      return false unless cfg.is_a?(Hash)
      #We expect hash to have 
      # key => etcd key to watch
      # target => Target config
      # source => Source template
      # id (optional)
    end

	  def locatecfgs
      Dir.glob("#{@cfgdir}/*.conf").map { |f| File.expand_path(f)}
    end

  end
end
