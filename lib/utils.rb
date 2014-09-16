#!/usr/bin/env ruby

module Reconfig
  Timeformat='%Y%m%d.%H:%M:%S'
  module Utils
    def logmsg(msg=nil)
      $stderr.puts "#{Time.now.strftime(Timeformat)} [PID #{$$.to_i}] - #{msg}" unless msg.nil?
    end
  end
end
