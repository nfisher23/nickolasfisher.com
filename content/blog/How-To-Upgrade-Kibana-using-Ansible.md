---
title: "How To Upgrade Kibana using Ansible"
date: 2019-03-01T00:00:00
draft: false
---

You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/some-ansible-examples).

In a previous post on [Provisioning a Server with Kibana](https://nickolasfisher.com/blog/How-to-Provision-a-Linux-VM-With-Kibana-Using-Ansible), we saw that it&#39;s very straightforward to get kibana on a box.

Upgrading Kibana is also very straightforward (and nowhere near as complicated as [upgrading elasticsearch](https://nickolasfisher.com/blog/How-to-do-a-Rolling-Upgrade-of-an-Elasticsearch-Cluster-Using-Ansible)). That will be the subject of this post.

First, initialize the ansible role using molecule, with vagrant as the VM provider:

``` bash
$ molecule init role -r upgrade-kibana -d vagrant
```

Then modify your **molecule/default/molecule.yml** file to look like:

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

We can bring in work from the previous post and include a dependency on our previous role to ensure Kibana is already there. Modify your **meta/main.yml** file to look like:

``` yaml
---
dependencies:
  - role: install-kibana
```

You should now be able to enter:

``` bash
$ molecule create &amp;&amp; molecule converge
```

And see kibana come up at 192.168.56.121:5601.

### Upgrading

We can now begin the upgrade process. We will follow a similar pattern to [upgrading logstash](https://nickolasfisher.com/blog/How-to-do-a-Rolling-Upgrade-of-Multiple-Logstash-Instances-Using-Ansible) and [upgrading elasticsearch](https://nickolasfisher.com/blog/How-to-do-a-Rolling-Upgrade-of-an-Elasticsearch-Cluster-Using-Ansible) by adding another collection of tasks to perform the upgrade when we see fit. Change your **tasks/main.yml** file to look like:

``` yaml
---
