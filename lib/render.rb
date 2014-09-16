#!/usr/bin/env ruby

require "erb"
require "json"
require 'digest/md5'
require 'yaml'

$LOAD_PATH.unshift(File.dirname(__FILE__))
require "utils.rb"

module Reconfig

  class Render
    #source is source template path
    def initialize(opts=Hash.new, valhash=Hash.new)
      @reconfigdata=valhash #In the template, all references to @reconfigdata
      @opts=opts
      @debug=@opts["debug"]
    end

    def process
      return false unless @opts.keys.length > 0
      newcontents=populate_template
      #p newcontents
      return false if newcontents=='RECONFIG-ERR'
      newsum=Digest::MD5.hexdigest(newcontents)
      if newsum==origmd5
        logmsg("NOOP for #{@opts["target"]} - No changes detected") if @debug
        return false
      else
        mode=@opts["notreally"] ? "NOOP" : "Modified"
        logmsg("Target config #{@opts["target"]} needs to be #{mode}")
        return false if @opts["notreally"] 
        #Modify file and set perms - TODO
       	begin
          File.open(@opts["target"], "w") {|f| f.write(newcontents) }
          return true 
        rescue Exception => e
          logmsg("Error writing to #{@opts["target"]} - #{e.inspect}")
          return false
        end 
      end
    end

    def populate_template
      begin
        template=ERB.new File.new(@opts["source"]).read, nil, "%"
     	  return template.result(binding) 
      rescue Exception => e
        logmsg("Error processing template #{@opts["source"]} - #{e.inspect} #{e.backtrace}")
        return 'RECONFIG-ERR' 
      end
    end

    def origmd5
      File.exists?(@opts["target"]) ? Digest::MD5.file(@opts["target"]).hexdigest : ""
    end

  end

end
