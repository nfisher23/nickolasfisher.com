---
title: "How to Simulate Distributed Systems in the Cloud with Vagrant"
date: 2018-10-28T14:28:13
draft: false
tags: [distributed systems, vagrant, DevOps]
---

In our last post on [simulating a cloud environment on your local machine](https://nickolasfisher.com/blog/how-to-set-up-a-private-local-network-on-your-pc-with-virtualbox),
we saw that we could use virtual box to create a virtual machine that could both talk to your local computer, with its own IP address, and to the internet.

There is a better way than manually configuring each server you want to spin up, however, and that better way is called [Vagrant](https://www.vagrantup.com/). **Vagrant is awesome**.

To recreate the same results as we just saw in our last post, download vagrant (and make sure you have virtual box installed). Then navigate to an empty directory and type:

`
$ vagrant init -m
`

This will create a VagrantFile in your current directory that looks like this:

```
Vagrant.configure("2") do |config|
  config.vm.box = "base"
end

```

The "base" image that we want here is found in the vagrant repository ubuntu/bionic64--that will typically contain the latest version of the Ubuntu 18 release. We also want to configure a virtual private network, just like we did before, so we will add networking information to make the IP recognizeable at 192.168.56.101:

```
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"
  config.vm.network "private_network", ip: "192.168.56.101"
end

```

If you run `$ vagrant up` at this point, you will be able to ssh into the machine with:

`$ vagrant ssh `

We can further specify how much memory and how many cores to dedicate to this virtual machine with:

```
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
    vb.cpus = 1
  end

```

You can then set up root access, just like you get when you spin up a VM in the cloud, with the following provisioning specifics (assuming you've got your ssh keys generated already):

```bash
  config.vm.provision "file", source: "~/.ssh/id_rsa.pub", destination: "~/.ssh/me.pub"
  config.vm.provision "shell", inline: "cat /home/vagrant/.ssh/me.pub >> /home/vagrant/.ssh/authorized_keys"
  config.vm.provision "shell", inline: "mkdir -p /root &amp;&amp; mkdir -p /root/.ssh/ &amp;&amp; cat /home/vagrant/.ssh/me.pub >> /root/.ssh/authorized_keys"

```

Your entire VagrantFile should now look like:

```
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"
  config.vm.network "private_network", ip: "192.168.56.101"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
    vb.cpus = 1
  end

  config.vm.provision "file", source: "~/.ssh/id_rsa.pub", destination: "~/.ssh/me.pub"
  config.vm.provision "shell", inline: "cat /home/vagrant/.ssh/me.pub >> /home/vagrant/.ssh/authorized_keys"
  config.vm.provision "shell", inline: "mkdir -p /root &amp;&amp; mkdir -p /root/.ssh/ &amp;&amp; cat /home/vagrant/.ssh/me.pub >> /root/.ssh/authorized_keys"
end

```

If you run `$ vagrant up` in the directory where this VagrantFile is located, you will be able to connect as root by running

`$ ssh root@192.168.56.101`

A word of warning: if you plan to do this consistently, your computer's default behavior is going to be to save the public key it gets from the local server, which will change every time you destroy and bring up virtual machines. You will then be understandably blocked if you try to connect to the same IP address which has a different SSH key on the other end. To fix this, on your **host system**, you can add this to your ~/.ssh/config file:

```
Host 192.168.56.*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

I am assuming here that you plan on keeping your IP addresses in the 192.168.56.(whatever) range here, which is a reasonable convention to assume.

You now have all the information you need to become a master of the distributed system universe. Remember us little people on your rise to prominence.
