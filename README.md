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
        --port PORT                  Etcd port. Default: 4001
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

### Using DNS SRV records ###

If you have `SRV` type record containing the hosts/ports of your etcd instances, e.g.

```
[smohan@Srinivasans-MacBook-Pro-3 tmp]$ host -t SRV _etcd._tcp.servdisc.somedomain.io
_etcd._tcp.servdisc.somedomain.io has SRV record 10 20 4001 etcd1.somedomain.io.
_etcd._tcp.servdisc.somedomain.io has SRV record 10 20 4001 etcd2.somedomain.io.
_etcd._tcp.servdisc.somedomain.io has SRV record 10 20 4001 etcd3.somedomain.io.
_etcd._tcp.servdisc.somedomain.io has SRV record 10 20 4001 etcd4.somedomain.io.
_etcd._tcp.servdisc.somedomain.io has SRV record 10 20 4001 etcd5.somedomain.io.
```

Then you can use `--srv _etcd._tcp.servdisc.somedomain.io` instead of having to pass `--host` & `--port` to `reconfig.rb`/`etcd-util.rb`. The resolver will pick a random one of many hosts to connect to (without looking at prio/weights for now).

## etcd-util.rb ##

You could use curl to add/update/delete etcd keys - See [Etcd](https://github.com/coreos/etcd) for details. Or you could use -

```
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -h
Usage: ./etcd-util.rb (options)
    -d, --debug                      Debug mode
    -h, --help                       Show this Help message.
        --host HOST                  Etcd host to connect to
    -k, --key KEY                    Key to work on. Required!
    -o, --operation OPERATION        Can be GET/SET/DEL/WATCH - Defaults to GET
        --port PORT                  Etcd port
    -r, --recursive                  Recursive mode. False by default. Matters for DEL
        --srv SRV-RECORD             Use DNS SRV record to locate the etcd host/port. If specified, overrides host/port
    -s, --ssl                        Use SSL mode
        --ssl_cafile PATH-TO-CA-FILE Path to SSL CA (cert auth) file
        --ssl_cert PATH-TO-SSL-CERT  Path to SSL cert
        --ssl_key PATH-TO-SSL-KEY    Path to SSL Key
        --ssl_passphrase Passphrase  Passphrase if SSL Key is encrypted
    -t, --ttl TTL                    TTL in seconds. Matters only for SET
    -v, --value VAL                  Value for the key. Required on SET
        --version                    Connect to etcd and dump version/leader info etc
```

Usage is pretty simple.
```
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /
[
  "/abc",
  "/test1"
]
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /abc
[
  "/abc/test1",
  "/abc/test2"
]
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k / -r
Running recursive find - May take a few secs...
{
  "/abc/test1/123": "hello",
  "/abc/test1/456": "hello",
  "/abc/test1/789": "hello",
  "/abc/test1/999": "hello998",
  "/abc/test2": "hello",
  "/test1/123": "hello",
  "/test1/456": "helloworld",
  "/test1/999": "helloworld"
}
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /abc/test2
{
  "/abc/test2": "hello"
}
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /abc/missing
Etcd::KeyNotFound /abc/missing
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /abc/missing -v not-missing -o set
Setting /abc/missing to not-missing
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /abc/missing
{
  "/abc/missing": "not-missing"
}
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /abc/missing -o del
root@ubuntu-kafka:~/Git/reconfig# ./etcd-util.rb -k /abc/missing
Etcd::KeyNotFound /abc/missing
```

## Variables you can access in the template ##

* `@reconfig` is a hash with keys `["data", "altdata", "watched"]`
* `@reconfig["data"]` - This hash gets populated with value based on the `key` you specified in config json.
* `@reconfig["altdata"]` - This hash gets populated with values based on keys you specified in `altkeys` param.
* `@reconfig["watched"]` - This string is set the full path of the "watched" etcd key i.e. `key` from your config json.

## Setup ##

`Reconfig` has no "global" config except for command line params from above. 

You build a json config to bind a Reconfig template and Etcd key to a target config file (that you want to rebuild each time the etcd key changes).

Two ways to do it:

1. The `etcd` key is a directory - And you want to pull the entire "tree" (i.e. `recursive=true`)
2. The `etcd` key being watched is a "file" - You just want its value.

## Configuration ##

### Config locations ###

By default, Reconfig will expect folder `/etc/reconfig` with folders `/etc/reconfig/conf.d` and `/etc/reconfig/templates`. You can override this by setting `--cfgdir` to an alternate path at runtime. I will assume you use `/etc/reconfig` in the examples.

* `/etc/reconfig/conf.d` - This will contain a JSON config file for reconfig for each etcd-key/target-conf-file combination.
* `/etc/reconfig/templates` - The `source` parameter specified in config json will map to a template file in this folder.


All config params in JSON:

* `id` - Set this to whatever makes sense to you. Its only used for logging and will be set to the path of the config.json if unspecified.
* `key` - Etcd key to watch.
* `source` - The template to use to render the final config file. Expected to be present in `/etc/reconfig/templates`
* `target` - The path to the config file Reconfig will generate when etcd key changes.
* `recursive` - Set to `true` if you want to watch a etcd directory (recursively)
* `pattern` - By default Reconfig will use erubis embedded patteen `<% %>` for your template files. Set a different pattern as needed.
* `altkeys` - Use this to fetch values from other etcd keys when the main key changes.
* `reloadcmd` - Command to use to (optionally) restart a service when the config file gets updated. 
* `checkcmd` - Use this to verify if generated config is valid (e.g. `varnishd -C -f /etc/varnish/default.vcl` for varnish if default.vcl was changed). This command must exit with a status `0` or else `reloadcmd` will be skipped. Matters only when `reloadcmd` is set.

## Sample configs ##

See [cfgtest/conf.d/](cfgtest/conf.d) and [cfgtest/templates](cfgtest/templates) for all examples.

Folder [./cfgtest/conf.d](cfgtest/conf.d) has a couple of sample JSON configs.

### Simple ###

Config file `/etc/reconfig/test1.json`:
```json
{
"id": "test1",
"source": "test1.conf.erb",
"target": "/tmp/test1.conf",
"key": "/test1",
"recursive": true
}
```


And the template `/etc/reconfig/templates/test1.conf.erb` is:

```erb
<% @reconfig["data"].keys.sort.each do |x| %>
KEY <%= x %> has VALUE <%= @reconfig["data"][x] %>
<% end %>
```

### You already use Chef/some-other solution and built config from a template already ###

By default, reconfig will assume that the embedded pattern in templates is `<% %>` (standard erubis pattern). However there may be scenarios where you want to use a different pattern, in this case, you can provide an additional param `pattern` in your reconfig config json and change your template to use that.

Sample config `/etc/reconfig/conf.d/test3_altpattern` is:
```json
{
"id": "test3_altpattern",
"source": "test3.conf.erb",
"target": "/tmp/test3.conf",
"key": "/test3",
"pattern": "#% %#",
"checkcmd": "/tmp/1.sh",
"reloadcmd": "/tmp/2.sh"
}
```

And your `/etc/reconfig/templates/test3.conf.erb` would look like this (Using `#% %#`):

```erb
#% @reconfig["data"].keys.each do |x| %#
Using alternate pattern, Key #%= x %# => #%= @reconfig["data"][x] %#
#% end %#
```

### You want to pull values from additional keys into your config as well ###

Pretty simple. Use `altkeys` in your reconfig json config.
Example: You want to watch etcd key `/test4` for changes and rebuild target config `/tmp/test4.conf` when it changes. However you also want to pull in the values from other etcd keys `/altkey1` and `/altkey2` into your target config file.

In this case, `/etc/reconfig/conf.d/test4.json` would look like:
```json
{
    "altkeys": {
        "akey1": "/altkey1",
        "akey2": "/altkey2"
    },
    "id": "test4_altkey",
    "key": "/test4",
    "recursive": false,
    "source": "test4.conf.erb",
    "target": "/tmp/test4.conf"
}
```

And a sample template `/etc/reconfig/templates/test4.conf.erb`:
```erb
This config uses 'altkeys' too. Using altkeys param, you can pull in values from other etcd keys into your config as well.
(The keys in altkeys are not watched for changed but rather fetched as-is whenever the main key changes)

The main key we watched for was "<%= @reconfig["watched"] %>".

Data based on main key (This key was being watched for changes):
<% @reconfig["data"].keys.each do |x| %>
KEY=<%= x %> VAL=<%= @reconfig["data"][x] %>
<% end %>

Data based on altkeys section (These are not watched but instead fetched from etcd whenever main key changes)
<% @reconfig["altdata"].keys.each do |thiskey| %>
Altkey=<%= thiskey %> - This points to a hash:
<%= JSON.pretty_generate(@reconfig["altdata"][thiskey]) %>
---

<% end %>
---

<% end %>

```
## Certain "design" assumptions ##

1. The same target config file cannot be monitored under multiple etcd keys.
2. The same etcd key cannot be monitored for multiple targets.
3. If you are watching a stub key (`recursive: false`) and it expires (etcd TTL), then its watcher will leave target config unchanged.

Basically - You cannot have a duplicate `key` or a `target` on a given system. That work for me now - Open to changing that if theres a need for it. Wanted to keep it simple for starters...

## TODO ##

1. Investigate if we can somehow watch many keys via same connection to etcd?
2. Get the whole tree/dir listing when a watched dir (`recursive=true`) updates instead of having to run a `find()` [like this](https://github.com/srinivasmohan/reconfig/blob/master/lib/worker.rb#L32)
3. Cleanup the `onetime` and init mode runs.


