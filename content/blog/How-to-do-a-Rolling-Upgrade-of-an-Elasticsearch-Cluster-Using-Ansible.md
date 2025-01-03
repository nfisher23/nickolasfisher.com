---
title: "How to do a Rolling Upgrade of an Elasticsearch Cluster Using Ansible"
date: 2019-03-16T23:17:03
draft: false
tags: [distributed systems, vagrant, ansible, DevOps]
---

You can see the source code for this blog post [on GitHub](https://github.com/nfisher23/some-ansible-examples).

In a previous post, we saw [how to provision a multi-node elasticsearch cluster using ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Multi-Node-Elasticsearch-Cluster-Using-Ansible). The problem with that post is that, by the time I was done writing it, _Elastic had already come out with a new version of elasticsearch_. I&#39;m being mildly facetious, but not really. They release new versions very quickly, even by the standards of modern software engineering.

It would be wise, therefore, to think about upgrading from the very beginning. The recommended way to upgrade versions of elasticsearch from 5.6 onwards is a [rolling upgrade](https://www.elastic.co/guide/en/elasticsearch/reference/current/rolling-upgrades.html). As you can see from that article, upgrading (even in place) elasticsearch is not trivial by any stretch of the imagination.

However, it can be done, and in this post I&#39;ll show you one way to do it using ansible.

### Doing the Upgrade

To start with, I&#39;ll create an ansible role using molecule to demo what is required:

```bash
$ molecule init role -r upgrade-elasticsearch-cluster -d vagrant
```

I&#39;m choosing Vagrant as my VM driver and calling this role upgrade-elasticsearch-cluster.

So I don&#39;t have to reinvent the wheel I&#39;m reusing the role that installs elasticsearch (version 6.3.0) by including it in my **meta/main.yml** file:

```yaml
---
dependencies:
  - role: install-elasticsearch-cluster

```

That role is still a WIP, and in fact I changed the discovery IP addresses to be 192.168.56.101-103, hardcoded in the configuration file. To demonstrate a minimum viable product for this example I&#39;ll reuse that **molecule/default/molecule.yml** platform&#39;s section:

```yaml
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

```yaml
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

```yaml
---
upgrade_es: false
```

Then, you can make your **tasks/main.yml** file look like:

```yaml
- include: upgrade_es.yml
  when: upgrade_es
```

And create a **tasks/upgrade\_es.yml** file, which will house all of the upgrade logic:

```yaml
---
# tasks file for upgrade-elasticsearch-cluster
- name: ensure elasticsearch already present
  service:
    name: elasticsearch
    state: started
  become: yes

- name: ensure elasticsearch is up and available
  wait_for:
    host: 127.0.0.1
    port: 9200
    delay: 5

- name: get elasticsearch to upgrade to
  get_url:
    dest: &#34;/etc/{{ es_version_to_upgrade_to }}&#34;
    url: &#34;https://artifacts.elastic.co/downloads/elasticsearch/{{ es_version_to_upgrade_to }}&#34;
    checksum: &#34;sha512:https://artifacts.elastic.co/downloads/elasticsearch/{{ es_version_to_upgrade_to }}.sha512&#34;
  become: yes

- name: perform upgrade process as root
  block:
    - name: disable shard allocation
      uri:
        url: http://127.0.0.1:9200/_cluster/settings
        body: &#39;{&#34;persistent&#34;:{&#34;cluster.routing.allocation.enable&#34;:&#34;none&#34;}}&#39; # specify no shard allocation
        body_format: json
        method: PUT

    - name: stop non essential indexing to speed up shard recovery
      uri:
        url: http://127.0.0.1:9200/_flush/synced
        method: POST
      ignore_errors: yes

    - name: get cluster id
      uri:
        url: http://127.0.0.1:9200
      register: pre_upgrade_cluster_info

    - name: shut down node
      service:
        name: elasticsearch
        state: stopped

    - name: upgrade node
      apt:
        deb: &#34;/etc/{{ es_version_to_upgrade_to }}&#34;

    - name: bring up node
      service:
        name: elasticsearch
        state: started
      notify: wait for elasticsearch to start

    - meta: flush_handlers

    - name: validate it joins cluster
      uri:
        url: http://127.0.0.1:9200
      register: post_upgrade_cluster_info
      until: pre_upgrade_cluster_info.json.cluster_uuid == post_upgrade_cluster_info.json.cluster_uuid
      retries: 3
      delay: 10

    - name: reenable shard allocation
      uri:
        url: http://127.0.0.1:9200/_cluster/settings
        body: &#39;{&#34;persistent&#34;:{&#34;cluster.routing.allocation.enable&#34;:null}}&#39; # reenabling the setting removes shard allocation
        body_format: json
        method: PUT

    - name: wait for elasticsearch to recover
      script: check_es_health.py
      register: es_recovery_response
      until: es_recovery_response.rc == 0
      retries: 15
      delay: 10
  become: yes

```

There is one script that has to run located at **files/check\_es\_health.py**. This is pretty simple:

```python
#!/usr/bin/python

import urllib2
import sys

response = urllib2.urlopen(&#34;http://127.0.0.1:9200/_cat/health&#34;)
body = response.read()
response.close()
if &#34;green&#34; in body:
    sys.exit(0)
else:
    sys.exit(1)

```

Finally, there is one handler in **handlers/main.yml** file that looks like:

```yaml
---
# handlers file for upgrade-elasticsearch-cluster
- name: wait for elasticsearch to start
  wait_for:
    host: 127.0.0.1
    port: 9200
    delay: 5
```

To run the [source code from github,](https://github.com/nfisher23/some-ansible-examples) you will have to first leave the upgrade\_es flag to be false. Then run:

```bash
$ molecule create &amp;&amp; molecule converge
```

After the VMs come up and they have working elasticsearch instances, you need to add the **serial: 1** flag at the top of the **molecule/default/playbook.yml** file. Then switch the **upgrade\_es** flag to **true**, and run:

```bash
$ molecule converge
```

The virtual machines will then be upgraded one by one, stopping until the instance comes up and is available.
