#!/usr/bin/env ruby
require 'bundler'
Bundler.require


$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "utils.rb"
include Reconfig::Utils

#Parse cmdline opts.
cli=Reconfig::Options.new
cli.parse_options
unless cli.config[:prefix].nil?
  abort "Key prefix must begin with a /" unless cli.config[:prefix]=~/^\//
end
cfg=Reconfig::Config.new(cli.config)

