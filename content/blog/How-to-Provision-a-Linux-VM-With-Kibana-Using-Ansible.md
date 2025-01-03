---
title: "How to Provision a Linux VM With Kibana Using Ansible"
date: 2019-03-01T00:00:00
draft: false
---

The corresponding source code for this post is available [on GitHub](https://github.com/nfisher23/some-ansible-examples).

[Kibana](https://www.elastic.co/products/kibana) is a fancy pants web application that tries to make data in Elasticsearch user-friendly. Rounding out the previous two posts on [how to install an elasticsearch cluster](https://nickolasfisher.com/blog/How-to-Provision-a-Multi-Node-Elasticsearch-Cluster-Using-Ansible) and [how to install multiple logstash hosts](https://nickolasfisher.com/blog/How-to-Install-Multiple-Logstash-Hosts-Using-Ansible), I will now show you how to stack kibana on top of them.

### Create the Ansible Role

Navigate to the directory you want the ansible role to reside and type:

``` bash
$ molecule init role -d vagrant -r install-kibana
```

I&#39;m using molecule to wrap vagrant and I&#39;m calling this role install-kibana.

We will put kibana on a single host, 192.168.56.121. To make this happen, adjust the _platforms_ section of your **molecule/default/molecule.yml** file to look like:

``` yaml
platforms:
  - name: kibana
    box: ubuntu/xenial64
    memory: 4096
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.121
      type: static

```

We provision this local VM with 4GB of RAM. You can bring up this VM at this point with:

``` bash
$ molecule create
```

First, we&#39;ll decide on the version of kibana we want to provision. To keep this compatible with the two posts mentioned above, we&#39;ll choose version 6.4.0, and update the **vars/main.yml** file to reflect the full name of the deb file we&#39;ll be grabbing in our playbook like so:

``` yaml
---
