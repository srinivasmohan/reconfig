#!/usr/bin/env ruby
require "etcd"
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "utils.rb"
require "config.rb"

module Reconfig
  class Worker
    include EM::Deferrable

    def initialize(opts=Hash.new)
      #$stderr.puts "INIT: "+JSON.pretty_generate(opts)
      @key=opts["key"]
      @id=opts["id"]
      @ckey=opts["id"] + "(Key: #{@key})"
      @src=opts["source"]
      @tgt=opts["target"]
      @mode=opts["recursive"]
      @reload=opts["reloadcmd"]
      @check=opts["checkcmd"] 
      @client=opts["client"] 
      @debug=opts["debug"]    
    end

    def debug!
      @debug=!@debug
    end

    def run
      modedesc=@recursive ? "TREE": "LEAF"
      logmsg("#{@ckey} - Watching #{@key} (#{modedesc})- Change #{@tgt} using #{@src}")
      loop do 
        begin
       	  val=@client.watch(@key, recursive: @mode)
          $stderr.puts "#{@ckey} - "
          p val 
        rescue Exception => e
          logmsg("#{@ckey} - Connectivity error to #{@host}:#{@port} - #{e.inspect}")
          sleep 30
        end 
      end    
    end
  end
end
