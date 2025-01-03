---
title: "How to Provision Multiple Logstash Hosts Using Ansible"
date: 2019-03-01T00:00:00
draft: false
---

The source code for this post can be found [on GitHub](https://github.com/nfisher23/some-ansible-examples).

[Logstash](https://www.elastic.co/products/logstash) primarily exists to extract useful information out of plain-text logs. Most applications have custom logs which are in whatever format the person writing them thought would look reasonable...usually to a human, and not to a machine. While countless future developer hours would be preserved if everything were just in JSON, that is sadly not even remotely the case, and in particular it&#39;s not the case for log files. Logstash aims to be the intermediary between the various log formats and Elasticsearch, which is the document database provided by Elastic as well.

This post will focus on writing an ansible playbook to provision two logstash hosts, each of which will receive logs from a beats input and forward the output to an elasticsearch cluster. See a previous post on [how to provision an elasticsearch cluster using ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Multi-Node-Elasticsearch-Cluster-Using-Ansible).

### Create the Ansible Role

Navigate to the directory you want to keep this ansible role and type:

``` bash
$ molecule init role -d vagrant -r install-logstash
```

I&#39;m choosing to use vagrant as a local VM provider and I&#39;m calling this role install-logstash.

Since we want to demonstrate multiple nodes, we&#39;ll adjust our **molecule/default/molecule.yml** file&#39;s _platforms_ section to look like this:

``` yaml
platforms:
  - name: lsNode1
    box: ubuntu/xenial64
    memory: 4096
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.111
      type: static
  - name: lsNode2
    box: ubuntu/xenial64
    memory: 4096
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.112
      type: static

```

This gives us two nodes with IP addresses of 192.168.56.(111-112), and each VM is an instance of ubuntu/xenial64 with 4GB of RAM.

At this point, running:

``` bash
$ molecule create
```

Will give you the two virtual machines outlined above.

I&#39;ll jump ahead here and set up a variable we&#39;re going to use in our playbook, which is the logstash version in a deb file that we&#39;re going to use:

``` yaml
