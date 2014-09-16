Reconfig
========


## What is reconfig ##

Manage app config files using data from etcd - Inspired by [Confd](https://github.com/kelseyhightower/confd)

The idea is simple. You have a constantly "changing" fleet of servers (e.g. frontend haproxy and many backend boxes - an auto scaled group maybe). Whenever a new backend is added, you want the frontend haproxy to know about it (i.e. config convergence) in a reasonable time (say under 5 minutes).

## How does this work ##

There are two components to this:

1. `Etcd` - [Etcd](https://github.com/coreos/etcd) is a highly available key/value store for config and service discovery.
2. `Reconfig` - This is a daemon thats watching specific keys on etcd and reacts when these keys change (When do keys change? Typically when you add/remove servers). Reconfig reacts to etcd "events" that are posted by your nodes coming up/going down.

## Why Reconfig and not chef/puppet/ansible/whatever ##

Chef/Puppet are great for building initial system but for nodes config to converge to the "current" required state means chef-client/puppet agent wake up very frequently. I did'nt want to set ridiculously low run intervals for these. So Reconfig was built to work with Chef where Chef sets up an initial config template and Reconfig uses that to populate the actual config files the system daemons would use.

So yes, while Reconfig can be used by itself, it complements Chef and is not a replacement IMHO.
Let chef build/partially-populate your config templates and let Reconfig modify them on the fly when servers are added/removed.

## Installation ##

```
git clone git@github.com:srinivasmohan/reconfig.git
cd reconfig
bundle install
```

### Etcd installation ###

Pick up an etcd release from [Etcd GH release page](https://github.com/coreos/etcd/releases) and install (gunzip, cp and chmod).

### Etcd in production ###

You may want to lock this down to specific allowed security groups / IP blocks. Also a good idea to use SSL and client authentication via SSL.

See [Reading and writing over HTTPS](https://github.com/coreos/etcd/blob/master/Documentation/security.md) for details on how to setup etcd in SSL mode.

## Command line opts ##

```
root@ubuntu-kafka:~/Git/reconfig# ./reconfig.rb -h
Usage: ./reconfig.rb (options)
    -c, --cfgdir CFGDIR              Toplevel config dir. Defaults to /etc/reconfig
    -d, --debug                      Enable debug mode.
    -h, --help                       Show this Help message.
        --host ETCDHOST              Etcd host to connect to. Default: 127.0.0.1
    -n, --notreally                  Display changes but do not modify target files. Default: false
    -o, --onetime                    Run onetime and exit
        --port PORT                  Etc port. Default: 4001
    -p, --prefix someprefix          Key prefix to use. Must begin with '/'. Default: empty
        --srv SRV-RECORD             Use DNS SRV record to locate the etcd host/port. If specified, overrides host/port
    -s, --ssl                        Use SSL mode
        --ssl_cafile PATH-TO-CA-FILE Path to SSL CA (cert auth) file
        --ssl_cert PATH-TO-SSL-CERT  Path to SSL cert
        --ssl_key PATH-TO-SSL-KEY    Path to SSL Key
        --ssl_passphrase Passphrase  Passphrase if SSL Key is encrypted
        --version                    Display version and exit.
```

The options and their purposes should be (sorta) self descriptive :-) 

If you supply any of the `--sslxxx` params, the supplied files MUST exist.
(These allow you to connect to an etcd cluster over SSL - assuming the cluster was setup for it).

## Setup ##

`Reconfig` has no "global" config except for command line params from above. 

You build a json config to bind a Reconfig template and Etcd key to a target config file (that you want to rebuild each time the etcd key changes).

Two ways to do it:

1. The `etcd` key is a directory - And you want to pull the entire "tree" (i.e. `recursive=true`)
2. The `etcd` key being watched is a "file" - You just want its value.


Folder [./cfgtest/conf.d](cfgtest/conf.d) has a couple of sample JSON configs.

e.g. `test1.json` has:

```json
{
"id": "test1",
"source": "test1.conf.erb",
"target": "/tmp/test1.conf",
"key": "/test1",
"recursive": true
}
```

The above is just for illustration, but in a real setup, you would also have -
* `checkcmd` - The command to be run to validate your config (e.g. `varnishd -C -f /etc/varnish/default.vcl`)
* `reloadcmd` - The command to run if `checkcmd` returns OK e.g. `service varnish reload`

And the template corresponding to it is [test1.conf.erb](cfgtest/templates/test1.conf.erb)

```erb
<% @reconfigdata.keys.sort.each do |x| %>
KEY <%= x %> has VALUE <%= @reconfigdata[x] %>
<% end %>
```

`@reconfigdata` will always be a Hash.

## Certain "design" assumptions ##

1. The same target config file cannot be monitored under multiple etcd keys.
2. The same etcd key cannot be monitored for multiple targets.

Basically - You cannot have a duplicate `key` or a `target` on a given system. That work for me now - Open to changing that if theres a need for it. Wanted to keep it simple for starters...

## TODO ##

1. Implement the `checkcmd` and `reloadcmd` functionality.
2. Investigate if we can somehow watch many keys via same connection to etcd?
3. Get the whole tree/dir listing when a watched dir (`recursive=true`) updates instead of having to run a `find()` [like this](https://github.com/srinivasmohan/reconfig/blob/master/lib/worker.rb#L32)
4. Cleanup the `onetime` and init mode runs.


