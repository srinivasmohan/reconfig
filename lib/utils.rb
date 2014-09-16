#!/usr/bin/env ruby

module Reconfig
  Timeformat='%Y%m%d.%H:%M:%S'
  module Utils
    def logmsg(msg=nil)
      $stderr.puts "#{Time.now.strftime(Timeformat)} [PID #{$$.to_i}] - #{msg}" unless msg.nil?
    end

    #Given a SRV type record, locate the host:port combination (pick one of many)
    def getHostInfo(srv=nil)
      return [nil,nil] if srv.nil?
      resolver=Resolv::DNS.new
      all=resolver.getresources(srv,Resolv::DNS::Resource::IN::SRV)
      return [nil,nil] if all.length==0
      rec=all[(rand(all.length)+1).to_i-1]
      return [ rec.target.to_s, rec.port.to_i ]
    end

  end #End of Utils


end
