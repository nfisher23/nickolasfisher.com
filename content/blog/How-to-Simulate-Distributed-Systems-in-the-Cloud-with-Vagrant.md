---
title: "How to Simulate Distributed Systems in the Cloud with Vagrant"
date: 2018-10-28T14:28:13
draft: false
tags: [distributed systems, vagrant, DevOps]
---

In our last post on [simulating a cloud environment on your local machine](https://nickolasfisher.com/blog/How-to-Set-Up-A-Private-Local-Network-On-Your-PC-With-VirtualBox),
we saw that we could use virtual box to create a virtual machine that could both talk to your local computer, with its own IP address, and to the internet.

There is a better way than manually configuring each server you want to spin up, however, and that better way is called [Vagrant](https://www.vagrantup.com/). **Vagrant is awesome**.

To recreate the same results as we just saw in our last post, download vagrant (and make sure you have virtual box installed). Then navigate to an empty directory and type:

`
$ vagrant init -m
`

This will create a VagrantFile in your current directory that looks like this:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;base&#34;
end

```

The &#34;base&#34; image that we want here is found in the vagrant repository ubuntu/bionic64--that will typically contain the latest version of the Ubuntu 18 release. We also want to configure a virtual private network, just like we did before, so we will add networking information to make the IP recognizeable at 192.168.56.101:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;ubuntu/bionic64&#34;
  config.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.101&#34;
end

```

If you run `$ vagrant up` at this point, you will be able to ssh into the machine with:

`$ vagrant ssh `

We can further specify how much memory and how many cores to dedicate to this virtual machine with:

```
  config.vm.provider &#34;virtualbox&#34; do |vb|
    vb.memory = &#34;1024&#34;
    vb.cpus = 1
  end

```

You can then set up root access, just like you get when you spin up a VM in the cloud, with the following provisioning specifics (assuming you&#39;ve got your ssh keys generated already):

```bash
  config.vm.provision &#34;file&#34;, source: &#34;~/.ssh/id_rsa.pub&#34;, destination: &#34;~/.ssh/me.pub&#34;
  config.vm.provision &#34;shell&#34;, inline: &#34;cat /home/vagrant/.ssh/me.pub &gt;&gt; /home/vagrant/.ssh/authorized_keys&#34;
  config.vm.provision &#34;shell&#34;, inline: &#34;mkdir -p /root &amp;&amp; mkdir -p /root/.ssh/ &amp;&amp; cat /home/vagrant/.ssh/me.pub &gt;&gt; /root/.ssh/authorized_keys&#34;

```

Your entire VagrantFile should now look like:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;ubuntu/bionic64&#34;
  config.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.101&#34;

  config.vm.provider &#34;virtualbox&#34; do |vb|
    vb.memory = &#34;1024&#34;
    vb.cpus = 1
  end

  config.vm.provision &#34;file&#34;, source: &#34;~/.ssh/id_rsa.pub&#34;, destination: &#34;~/.ssh/me.pub&#34;
  config.vm.provision &#34;shell&#34;, inline: &#34;cat /home/vagrant/.ssh/me.pub &gt;&gt; /home/vagrant/.ssh/authorized_keys&#34;
  config.vm.provision &#34;shell&#34;, inline: &#34;mkdir -p /root &amp;&amp; mkdir -p /root/.ssh/ &amp;&amp; cat /home/vagrant/.ssh/me.pub &gt;&gt; /root/.ssh/authorized_keys&#34;
end

```

If you run `$ vagrant up` in the directory where this VagrantFile is located, you will be able to connect as root by running

`$ ssh root@192.168.56.101`

A word of warning: if you plan to do this consistently, your computer&#39;s default behavior is going to be to save the public key it gets from the local server, which will change every time you destroy and bring up virtual machines. You will then be understandably blocked if you try to connect to the same IP address which has a different SSH key on the other end. To fix this, on your **host system**, you can add this to your ~/.ssh/config file:

```
Host 192.168.56.*
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

I am assuming here that you plan on keeping your IP addresses in the 192.168.56.(whatever) range here, which is a reasonable convention to assume.

You now have all the information you need to become a master of the distributed system universe. Remember us little people on your rise to prominence.
