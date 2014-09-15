Reconfig
========


## What is reconfig ##

Manage app config files using data from etcd - Inspired by [Confd](https://github.com/kelseyhightower/confd)

The idea is simple. You have a constantly "changing" fleet of servers (e.g. frontend haproxy and many backend boxes - an auto scaled group maybe). Wheneven a new backend is added, you want the frontend haproxy to know about it (i.e. config convergence) in a reasonable time (say under 5 minutes).

## How does this work ##

There are two components to this:

1. `Etcd` - [Etcd](https://github.com/coreos/etcd) is a highly available key/value store for config and service discovery.
2. `Reconfig` - This is a daemon thats watching specific keys on etcd and reacts when these keys change (When do keys change? Typically when you add/remove servers). Reconfig reacts to etcd "events" that are posted by your nodes coming up/going down.

This is a work in progress.

## Why Reconfig and not chef/puppet/ansible/whatever ##

Chef/Puppet are great for building initial system but for nodes config to converge to the "current" required state means chef-client/puppet agent wake up very frequently. I did'nt want to set ridiculously low run intervals for these. So Reconfig was built to work with Chef where Chef sets up an initial config template and Reconfig uses that to populate the actual config files the system daemons would use.

So yes, while Reconfig can be used by itself, it complements Chef and is not a replacement IMHO.

