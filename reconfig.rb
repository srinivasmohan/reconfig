#!/usr/bin/env ruby
require 'bundler'
Bundler.require
require 'erb'

$LOAD_PATH.unshift(File.dirname(__FILE__)+'/lib')
require "utils.rb"
include Reconfig::Utils

x=Reconfig::Config.new

