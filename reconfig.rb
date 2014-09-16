#!/usr/bin/env ruby
require 'bundler'
Bundler.require


$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "utils.rb"
require "version.rb"
require "worker.rb"
include Reconfig::Utils

#Parse cmdline opts.
cli=Reconfig::Options.new
cli.parse_options
if cli.config[:version]
  logmsg("Reconfig version #{Reconfig::VERSION}")
  exit
end

unless cli.config[:prefix].nil?
  abort "Key prefix must begin with a /" unless cli.config[:prefix]=~/^\//
end
recfg=Reconfig::Config.new(cli.config)

if cli.config[:onetime]
  all=[]
  recfg.configs.each_pair do |thiskey,val|
   thiswconf=val.dup
   thisw=Reconfig::Worker.new(thiswconf.merge!({"debug" => cli.config[:debug], "client"=>recfg.client, "onetime" => true}))
   all << Thread.new { thisw.run } 
  end
  all.each {|t| t.join; }
else

  EM.run {
    recfg.configs.each_pair do |thiskey,val|
     logmsg("Setting up KeyWatch for #{thiskey}")
     thiswconf=val.dup
     thisw=Reconfig::Worker.new(thiswconf.merge!({"debug" => cli.config[:debug], "client"=>recfg.client, "onetime" => cli.config[:onetime] }))
     Thread.new do 
       thisw.run
     end 
    end 

    reaper = Proc.new { logmsg("Exiting!"); EM.stop  }
    Signal.trap "TERM", reaper
    Signal.trap "INT", reaper
    Signal.trap "USR1", Proc.new { recfg.debug! }
  }

end
logmsg("Finished.")
