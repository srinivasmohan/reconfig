#!/usr/bin/env ruby
require "etcd"
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "utils.rb"
require "config.rb"

module Reconfig
  class Worker
    include EM::Deferrable

    def initialize(opts=Hash.new)
      $stderr.puts "INIT: "+JSON.pretty_generate(opts)
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
      @nr=opts.has_key?("notreally") && opts["notreally"] ? true : false   
    end

    def debug!
      @debug=!@debug
    end

    #This stupidity to fetch a full tree when a recursive watch triggers.
    def find(key=nil,mode=false)
      rethash=Hash.new
      obj=@client.get(key,recursive: mode)
      if obj.node.dir
        childkeys=obj.children.map {|x| x.key }
        p childkeys
        if !mode
          return childkeys
        else
          childkeys.each do |x|
            rethash.merge!(find(x,mode))
          end 
        end
      else
        rethash[key]=obj.value
      end
      rethash
    end

    #Hmmm... If we are watching a tree recursively, how can we get back a list of keys/values without having to fetch it?
    def run
      modedesc=@mode ? "Recursive(Tree)": "SingleKey(Leaf)"
      logmsg("#{@ckey} - Watching #{@key} (#{modedesc})- Change #{@tgt} using #{@src}")
      loop do 
        begin
       	  obj=@client.watch(@key, recursive: @mode)
          val=find(@key,@mode)
          logmsg("Key #{@key} changed (Mode=#{modedesc}) => #{val}")
        rescue Exception => e
          logmsg("#{@ckey} - Connectivity error to #{@host}:#{@port} - #{e.inspect}")
          sleep 30
        end 
      end    
    end
  end #end of Worker
end #end of module
