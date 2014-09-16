#!/usr/bin/env ruby
require 'bundler'
Bundler.require


$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "utils.rb"
require "version.rb"
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
recfg.connect

EM.run {
  recfg.configs.keys.each do |thiskey|


  end 

  reaper = Proc.new { logmsg("Exiting!"); EM.stop  }
  Signal.trap "TERM", reaper
  Signal.trap "INT", reaper
  Signal.trap "USR1", Proc.new { recfg.debug! }
}
