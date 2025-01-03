---
title: "A VagrantFile for Elasticsearch, Logstash, and Kibana (On Three Different Servers)"
date: 2018-11-01T00:00:00
draft: false
---

[Elasticsearch, Logstash, and Kibana](https://www.elastic.co/), commonly referred to as ELK or the Elastic Stack, is a set of tools that can, well do a lot of things. It is most famous for its logging and analytics capabilities.

In a nutshell:

1. Elasticsearch is a distributed NoSQL database with automatic indexing, and is designed primarily for &#34;scalability&#34;--in other words, redundancy via sharding and clustering across multiple servers, and a document-based philosophy (and, you know, search).
2. Kibana is a dashboard designed primarily to be a GUI on top of the Elasticsearch database, with cool features like visualization.
3. Logstash can send formatted logs to Elasticsearch and filter out logs that aren&#39;t relevant, typically by receiving them from Filebeats.

This is not an exhaustive list of all the things you can do with these tools, and this isn&#39;t even taking into account [beats](https://www.elastic.co/products/beats), but is usually where people start when they are introduced to the Elastic Stack.

So, now we want to play around with all of it, and we&#39;ve decided to use [Vagrant](https://www.vagrantup.com/) to provision some local virtual machines. While this is a good starting point/sandbox, keep in mind that there is no security with the following setup, and in any production environment not having security baked in would be a very bad thing to do.

First, we&#39;ll set up the VagrantFile. Navigate to the directory you want to set this up in and type:

``` bash
$ vagrant init -m
```

Then set up a VagrantFile like:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;ubuntu/bionic64&#34;

  config.vm.provider :virtualbox do |vb|
    vb.memory = 3072
    vb.cpus = 1
  end

  config.vm.define &#34;elasticsearch&#34; do |elasticsearch|
    elasticsearch.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.111&#34;
    elasticsearch.vm.provision :shell, path: &#34;elasticsearch-provision.sh&#34;
  end

  config.vm.define &#34;kibana&#34; do |kibana|
    kibana.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.112&#34;
    kibana.vm.provision :shell, path: &#34;kibana-provision.sh&#34;
  end

  config.vm.define &#34;logstash&#34; do |logstash|
    logstash.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.113&#34;
    logstash.vm.provision :shell, path: &#34;logstash-provision.sh&#34;
  end
end
```

You&#39;ll need three shell scripts in the same directory called &#34;elasticsearch-provision.sh&#34;, &#34;kibana-provision.sh&#34;, and &#34;logstash-provision.sh&#34;.

Let&#39;s start with the Elasticsearch shell script. From [the official Elasticsearch install guide for version 6.4](https://www.elastic.co/guide/en/elasticsearch/reference/6.4/index.html):

&gt; Elasticsearch requires at least Java 8. Specifically as of this writing,
&gt; it is recommended that you use the Oracle JDK version 1.8.0\_131.

So we need to:

1. Install Java 8

2. Install Elasticsearch
3. Configure it to listen on a specified port on the server
4. Ensure the service is running, and runs on server boot up time

The steps can be expressed in a bash script like so (elasticsearch-provision.sh):

``` bash
#!/bin/bash

