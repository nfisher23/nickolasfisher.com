---
title: "How to Set Up a Local Unsecured Postgres Virtual Machine (for testing)"
date: 2018-11-01T00:00:00
draft: false
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/integration-testing-postgres-and-spring/tree/master/postgres-vm-sandbox).

While we can always install [PostgreSQL](https://www.postgresql.org/) on our host machine, it&#39;s a much cleaner solution to create something like a local virtual machine with [Vagrant](https://www.vagrantup.com/) or a container using [Docker.](https://www.docker.com/) That way, any changes we make to the database and then forget about are not around as soon as we destroy either the container or the virtual machine. It is one more way to tighten that feedback loop we need as developers.

I&#39;ll provide an example using Vagrant in this post, though migrating to Docker should be fairly straightforward once you get the steps. Note that the following example is not even remotely secure, and if you use this method for anything but local sandboxing you will almost certainly get a cyber smack across the face at some point in the future.

First, let&#39;s set up a simple VagrantFile that defaults to using the IP 192.168.56.111:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;ubuntu/bionic64&#34;

  config.vm.provider &#34;virtualbox&#34; do |v|
    v.memory = 2048
    v.cpus = 1
  end

  config.vm.provision :shell, path: &#34;postgres-provision.sh&#34;
  config.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.111&#34;
end
```

In the same directory as the VagrantFile, we&#39;re going to need a file called &#34;postgres-provision.sh&#34;. We need to:

1. Install PostgreSQL
2. Set the default behavior (which is normally just localhost) to listen to all addresses (which will include our static, local IP).
3. Allow any authentication mechanism
4. Restart the service

The following bash script accomplishes that, and also creates a test database called &#34;testdb&#34; as another place to toy around:

``` bash
#!/bin/bash

sudo apt-get update &amp;&amp; sudo apt-get -y install postgresql

