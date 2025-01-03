---
title: "How to Provision a Standalone Consul Server with Ansible"
date: 2019-04-01T00:00:00
draft: false
---

You can find the source code for this post [on GitHub](https://github.com/nfisher23/some-ansible-examples/tree/master/consul-server).

[Consul](https://www.consul.io/) is a distributed service discovery engine. It&#39;s primary purpose is to track and manage services that interact with it--usually via an HTTP API. It monitors the health of services in near real time, providing a more robust way of routing services to healthy and responsive nodes.

In this post, we&#39;ll look at provisioning a standalone consul server with Ansible. This is not recommended for production, both because this Consul Server is a single point of failure and because there is no security in this example, but it is a good starting place to Proof-of-Concept the technology.

You will need Molecule, Ansible, VirtualBox, and Vagrant for this example to work. It will be easier for you to follow along if you are already familiar with those tools.

### Create the Ansible Role

Start by running:

``` bash
$ molecule init role -r consul-server -d vagrant
```

This creates a new Ansible role, wrapping Molecule around it, and chooses Vagrant as the VM driver.

Consul is written using Golang--a huge draw of Golang is that it is almost always compiled ahead-of-time, to a binary executable of the target machine. To get consul to run on our machine, then, it suffices for us to figure out what the OS of that machine will be. In this example, we are using Ubuntu, which is a Linux distribution, and we can thus install consul\_(version)\_linux\_amd64.zip (see the [Consul Downloads](https://www.consul.io/downloads.html) page for any other distributions).

In your ansible role, modify your **vars/main.yml** file to look like:

``` yaml
---
