---
title: "How to do a Rolling Upgrade of an Elasticsearch Cluster Using Ansible"
date: 2019-03-01T00:00:00
draft: false
---

You can see the source code for this blog post [on GitHub](https://github.com/nfisher23/some-ansible-examples).

In a previous post, we saw [how to provision a multi-node elasticsearch cluster using ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Multi-Node-Elasticsearch-Cluster-Using-Ansible). The problem with that post is that, by the time I was done writing it, _Elastic had already come out with a new version of elasticsearch_. I&#39;m being mildly facetious, but not really. They release new versions very quickly, even by the standards of modern software engineering.

It would be wise, therefore, to think about upgrading from the very beginning. The recommended way to upgrade versions of elasticsearch from 5.6 onwards is a [rolling upgrade](https://www.elastic.co/guide/en/elasticsearch/reference/current/rolling-upgrades.html). As you can see from that article, upgrading (even in place) elasticsearch is not trivial by any stretch of the imagination.

However, it can be done, and in this post I&#39;ll show you one way to do it using ansible.

### Doing the Upgrade

To start with, I&#39;ll create an ansible role using molecule to demo what is required:

``` bash
$ molecule init role -r upgrade-elasticsearch-cluster -d vagrant
```

I&#39;m choosing Vagrant as my VM driver and calling this role upgrade-elasticsearch-cluster.

So I don&#39;t have to reinvent the wheel I&#39;m reusing the role that installs elasticsearch (version 6.3.0) by including it in my **meta/main.yml** file:

``` yaml
---
dependencies:
  - role: install-elasticsearch-cluster

```

That role is still a WIP, and in fact I changed the discovery IP addresses to be 192.168.56.101-103, hardcoded in the configuration file. To demonstrate a minimum viable product for this example I&#39;ll reuse that **molecule/default/molecule.yml** platform&#39;s section:

``` yaml
platforms:
  - name: elasticsearchNode1
    box: ubuntu/xenial64
    memory: 4096
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.101
      type: static
  - name: elasticsearchNode2
    box: ubuntu/xenial64
    memory: 4096
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.102
      type: static
  - name: elasticsearchNode3
    box: ubuntu/xenial64
    memory: 4096
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.103
      type: static
```

This creates three virtual machines that will be provisioned with elasticsearch and join the same cluster. Also be sure to add some host variables to your **molecule.yml** file:

``` yaml
provisioner:
  name: ansible
  inventory:
    host_vars:
      elasticsearchNode1:
        node_name: es_node_1
        is_master_node: true
        es_version_to_upgrade_to: elasticsearch-6.5.3.deb
      elasticsearchNode2:
        node_name: es_node_2
        is_master_node: true
        es_version_to_upgrade_to: elasticsearch-6.5.3.deb
      elasticsearchNode3:
        node_name: es_node_3
        is_master_node: false
        es_version_to_upgrade_to: elasticsearch-6.5.3.deb
```

We will eventually be upgrading to version 6.5.3, and that will become clear soon.

We will create a boolean flag that allows us to upgrade elasticsearch and call it upgrade\_es, change your **defaults/main.yml** file to look like this:

``` yaml
---
upgrade_es: false
```

Then, you can make your **tasks/main.yml** file look like:

``` yaml
- include: upgrade_es.yml
  when: upgrade_es
```

And create a **tasks/upgrade\_es.yml** file, which will house all of the upgrade logic:

``` yaml
---
