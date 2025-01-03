---
title: "How to Set Up A Private Local Network On Your PC With VirtualBox"
date: 2018-10-28T14:27:31
draft: false
tags: [distributed systems]
---

While you can always spin up a [Digital Ocean](https://www.digitalocean.com/) or [Linode](https://www.linode.com/) Virtual Private Server to toy around with,
that both costs money (pennies, at most a dollar or two, admittedly) and isn&#39;t an extremely fast feedback loop for server provisioning. What we really want, as developers, is a way to test out an idea, see its feasibility, and preferably
tinker with that idea until it&#39;s solid.

The goal can be summed up with an example: say we have a chunk of distributed microservices across various machines, and to debug, to date, we have had to go onto each machine and manually inspect the logs for that particular microservice. If there are multiple microservices, we might have to look in three or four different places for log information to track down the problem. So, we say to ourselves, we want to aggregate our logs into one place to save time, monitor security abnormalities, and track down any problems before they become big problems. After researching a bit, we realize that [The Elastic Stack](https://www.elastic.co/products) is the best option for us moving forward.

The Elastic Stack has three principle components: Elasticsearch, Logstash, and Kibana (ELK). There are other things that interact with these core applications as well, and the big point to all of it is that it is distributed. Elasticsearch is a distributed data store and the microservices whose logs we want to aggregate are obviously already distributed.
How are we going to prove that this can actually work without having multiple machines interacting with each other? Rephrased in a software developers automatic vocabulary,
how can we _quickly_ and _cheaply_ prove that this will actually work? We need a place
to toy around with these applications, and shorten our feedback loop as tightly as possible.

One way, as mentioned above, was to spin up some DO or Linode VPS&#39;s and do our tinkering on there. Another option is to use [VirtualBox](https://www.virtualbox.org/) to create local,
virtual machines, and configure them to accept connections just like a virtual private server in the cloud would. That is the subject of this tutorial (the next step, and the subject of the next post, is to [use Vagrant](https://nickolasfisher.com/blog/How-to-Simulate-Distributed-Systems-in-the-Cloud-with-Vagrant). **Vagrant is awesome**.)

### Prerequisites

Download virtual box, and [download the latest ubuntu server](https://www.ubuntu.com/download/server). The version we&#39;ll use for this tutorial is 18.04 LTS. Then, you can follow this [tutorial on setting up Ubuntu Server on Virtual Box](https://ilearnstack.com/2013/04/13/setting-ubuntu-vm-in-virtualbox/).

### How to talk to a &#34;guest&#34; virtual machine from your &#34;host&#34; machine

In virtual box world, your &#34;host&#34; machine is your regular operating system, which boots up when you start your computer. Any &#34;guest&#34; machine, then, is
whatever virtual box instance you have set up. Since what we want is to be able to connect to a server using ssh, as we would in a real VM, we have to
tinker a bit with our virtual box instance.

Make sure your ubuntu VM guest machine is powered off, then go to **Global Tools**. Click on &#34;VirtualBox Host-Only Ethernet Adapter,
and have the following settings configured:

- Server Address: 192.168.56.100
- Server Mask: 255.255.255.0
- Lower Address Bound: 192.168.56.101
- Upper Address Bound: 192.168.56.254

Now go to your virtual machine instance, click on **Network**, and configure the adapters like so:

- Adapter 1: NAT, cable connected (this should already be configured)
- Adapter 2: Host-only Adapter, VirtualBox Host-Only Ethernet Adapter, Allow All, cable connected

Now power up your machine and click onto it using the GUI. Type

`$ ip a`

You should see a localhost loopback instance, and two named ethernet interfaces. The named interfaces will be the NAT configuration (which lets your virtual machine
talk to the internet) and the host-only ethernet adapter. By default, the host-only ethernet adapter will not advertise itself anywhere.

For me, the NAT interface was enp0s3, and the host-only interface was named enp0s8. We will have to change the host-only interface to be a static IP address, which, for Ubuntu 18.04, is done in the
`/etc/netplan/99_config.yaml` file. If the file doesn&#39;t exist, create it.

Your configuration file should be changed to look like this:

```yaml
network:
  ethernets:
    enp0s3:
      addresses: []
      dhcp4: true
    enp0s8:
      addresses: []
        - 192.168.56.101/24
  version: 2

```

Now, type

`$ sudo netplan apply`

And your machine is configured. You can validate that it works by connecting via SSH on your local machine:

`$ ssh your_username@192.168.56.101`

While you can do this for every VM that you want to configure, including multiple ones, I would instead recommend you move on from this exercise and shorten the feedback loop by [setting up Vagrant to simulate a cloud-like environment](https://nickolasfisher.com/blog/How-to-Simulate-Distributed-Systems-in-the-Cloud-with-Vagrant).
