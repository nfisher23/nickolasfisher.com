---
title: "How to Set Up a Local Unsecured Postgres Virtual Machine (for testing)"
date: 2018-11-24T12:47:47
draft: false
tags: [vagrant, bash, DevOps, postgreSQL]
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/integration-testing-postgres-and-spring/tree/master/postgres-vm-sandbox).

While we can always install [PostgreSQL](https://www.postgresql.org/) on our host machine, it's a much cleaner solution to create something like a local virtual machine with [Vagrant](https://www.vagrantup.com/) or a container using [Docker.](https://www.docker.com/) That way, any changes we make to the database and then forget about are not around as soon as we destroy either the container or the virtual machine. It is one more way to tighten that feedback loop we need as developers.

I'll provide an example using Vagrant in this post, though migrating to Docker should be fairly straightforward once you get the steps. Note that the following example is not even remotely secure, and if you use this method for anything but local sandboxing you will almost certainly get a cyber smack across the face at some point in the future.

First, let's set up a simple VagrantFile that defaults to using the IP 192.168.56.111:

```
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"

  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
    v.cpus = 1
  end

  config.vm.provision :shell, path: "postgres-provision.sh"
  config.vm.network "private_network", ip: "192.168.56.111"
end
```

In the same directory as the VagrantFile, we're going to need a file called "postgres-provision.sh". We need to:

1. Install PostgreSQL
2. Set the default behavior (which is normally just localhost) to listen to all addresses (which will include our static, local IP).
3. Allow any authentication mechanism
4. Restart the service

The following bash script accomplishes that, and also creates a test database called "testdb" as another place to toy around:

```bash
#!/bin/bash

sudo apt-get update &amp;&amp; sudo apt-get -y install postgresql

# set the default to listen to all addresses
sudo sed -i "/port*/a listen_addresses = '*'" /etc/postgresql/10/main/postgresql.conf

# allow any authentication mechanism from any client
sudo sed -i "$ a host all all all trust" /etc/postgresql/10/main/pg_hba.conf

# create db named testdb
sudo su postgres -c "createdb testdb"

# restart the service to allow changes to take effect
sudo service postgresql restart
```

If you run

```bash
$ vagrant up
```

You should see your VM go live and be ready to play in your sandbox.
