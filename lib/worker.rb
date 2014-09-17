#!/usr/bin/env ruby
require "etcd"
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "utils.rb"
require "config.rb"
require "render.rb"
require "mixlib/shellout"

module Reconfig
  class Worker
    include EM::Deferrable

    def initialize(opts=Hash.new)
      @opts=Hash.new
      #$stderr.puts "INIT: "+JSON.pretty_generate(opts)
			%w{key id source target reloadcmd checkcmd client pattern}.each do |x|
        @opts[x]=opts[x]
      end
      @opts["splay"]=opts.has_key?("splay") ? rand(opts["splay"].to_i)+1 : rand(10)+1 #Time to wait before reloading svc.
      %w{recursive debug notreally onetime}.each do |x|
        @opts[x]=opts.has_key?(x) && opts[x] ? true: false
      end
      @key=opts["key"]
      @ckey=opts["id"] + " [Key #{@key}]"
      @client=opts["client"] 
      @debug=opts["debug"] 
    end

    def debug!
      @debug=!@debug
    end

    def shellcmd(cmdstr)
      stat=false
      cmd=Mixlib::ShellOut.new(cmdstr)
      begin
        cmd.run_command
        if cmd.error!.nil?
          stat=true
        else
          $stderr.puts "#{cmdstr} errors:\n#{cmd.error!}"
        end
        if @debug
          logmsg("#{@ckey}: Ran [#{cmdstr}]")
          $stderr.puts "#{@ckey}: STDOUT #{cmd.stdout}"
          $stderr.puts "#{@ckey}: STDERR #{cmd.stderr}"
        end
      rescue Exception => e
        logmsg("Failed to run #{cmdstr} - #{e.inspect}")
      end
      return stat
    end

    #This stupidity to fetch a full tree when a recursive watch triggers.
    def find(key=nil,mode=false)
      rethash=Hash.new
      obj=@client.get(key,recursive: mode)
      if obj.node.dir
        childkeys=obj.children.map {|x| x.key }
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

    #Hmmm... If we are watching an etcd dir recursively, how can we get back a list of keys/values without having to fetch it?
    def run
      logmsg("#{@ckey} - [#{ @opts["recursive"] ? "Recursive/Tree": "SingleKey/Leaf" }]")
      loop do 
        begin
          val=nil
          if !@opts["onetime"]
       	    obj=@client.watch(@key, recursive: @opts["recursive"])
            logmsg("Key #{@key} changed #{obj}")
            val=find(@key,@opts["recursive"])
          else
            val=find(@key,@opts["recursive"])
          end
          logmsg("Key #{@key} contains #{val}") if @debug
          renderer=Reconfig::Render.new(@opts.dup, val)
          filechanged=renderer.process
          if filechanged
            logmsg("#{@ckey} - Target config #{@opts["target"]} modified.")
            unless @opts["reloadcmd"].nil?
              checkstatus=@opts["checkcmd"].nil? ? true : shellcmd( @opts["checkcmd"] )
              if checkstatus
                logmsg("#{@ckey}: Will restart via [#{@opts["reloadcmd"]}] in #{@opts["splay"]} secs")
                sleep @opts["splay"]
                shellcmd(@opts["reloadcmd"])
              else
                logmsg("#{@ckey} - Check [#{@opts["checkcmd"]}] failed! Skipping restart!")
              end
            end     
          end
        rescue Exception => e
          logmsg("#{@ckey} - Connectivity error to #{@host}:#{@port} - #{e.inspect}")
          sleep 15
        end 
        break if @opts["onetime"]
      end    
    end
  end #end of Worker
end #end of module
