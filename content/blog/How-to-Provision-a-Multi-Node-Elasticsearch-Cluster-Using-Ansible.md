---
title: "How to Provision a Multi Node Elasticsearch Cluster Using Ansible"
date: 2019-03-03T23:15:27
draft: false
tags: [distributed systems, vagrant, ansible, the elastic stack, DevOps]
---

You can see the sample code for this tutorial [on GitHub.](https://github.com/nfisher23/some-ansible-examples)

[Elasticsearch](https://www.elastic.co/products/elasticsearch) is a distributed, NoSQL, document database, built on top of Lucene. There are so many things I could say about Elasticsearch, but instead I&#39;ll focus on how to install a simple 3-node cluster with an Ansible role. The following example will not have any security baked into it, so it&#39;s really just a starting point to get you up and running.

To properly work along with the following example, you&#39;ll need ansible and probably vagrant (with virtualbox).

### Initializing an Ansible Role

I&#39;m electing to use [Molecule](https://nickolasfisher.com/blog/How-to-do-Test-Driven-Development-on-Your-Ansible-Roles-Using-Molecule) to initialize an ansible role for me, and vagrant as the VM provider:

```bash
$ molecule init role -d vagrant -r install-elasticsearch-cluster
$ cd install-elasticsearch-cluster

```

We can use some convenient yaml syntax to define some inventory for fleshing out our role in the **molecule/default/molecule.yml** file. First, adjust the platforms section to look like the following:

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

This will instruct molecule to create three virtual machines, each of the Ubuntu/xenial64 distribution, with 4GB of RAM, and IP addresses of 192.168.56.(101-103). By specifying the name option, we also have implicitly specified that our &#34;inventory&#34; for any local testing will contain the host names elasticsearchNode1, elasticsearchNode2, and elasticsearchNode3. This is important, as we can then define host variables for each of these in our playbooks in the provisioner section:

```yaml
provisioner:
  name: ansible
  inventory:
    host_vars:
      elasticsearchNode1:
        node_name: es_node_1
        is_master_node: true
      elasticsearchNode2:
        node_name: es_node_1
        is_master_node: true
      elasticsearchNode3:
        node_name: es_node_1
        is_master_node: false

```

We will be using these variables in a bit.

Actually installing Elasticsearch is pretty straightforward if you elect to use the **deb** distribution file. All we need is Java 8 as a prerequisite, which is available via the package manager on xenial64. Set your **tasks/main.yml** file to look like:

```java
---
- name: ensure Java is installed
  apt:
    name: &#34;openjdk-8-jdk&#34;
    state: present
    update_cache: yes
  become: yes

- name: download deb package
  get_url:
    dest: &#34;/etc/{{ elasticsearch_deb_file }}&#34;
    url: &#34;https://artifacts.elastic.co/downloads/elasticsearch/{{ elasticsearch_deb_file }}&#34;
    checksum: &#34;sha512:https://artifacts.elastic.co/downloads/elasticsearch/{{ elasticsearch_deb_file }}.sha512&#34;
  become: yes

- name: install from deb package
  apt:
    deb: &#34;/etc/{{ elasticsearch_deb_file }}&#34;
  become: yes

```

We need to add, at a minimum, some variables to work with. For brevity&#39;s sake I&#39;ll include some variables which will become important later. Edit your **defaults/main.yml** file to look like:

```yaml
node_name: example_node
is_master_node: true

elasticsearch_deb_version: 6.3.0
elasticsearch_deb_file: elasticsearch-{{ elasticsearch_deb_version }}.deb
cluster_name: my_cluster_name
elasticsearch_http_port_range: 9200-9300

```

The deb file automatically includes a systemd service file. By default, it looks for elasticsearch configuration in the /etc/elasticsearch/elasticsearch.yml file. The real meat of installing elasticsearch effectively (as is the case with most tools like it) is in the configuration, and that&#39;s where we have to go.

We can use a Jinja2 template to make this playbook more reuseable, utilizing many of the variables that were previously defined. First, create a **templates/elasticsearch.yml.j2** file from your root directory, and populate it with the following:

```yaml
cluster.name: {{ cluster_name }}
network:
  publish_host: {{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }}
  bind_host: 0.0.0.0

http.port: {{ elasticsearch_http_port_range }}
transport.tcp.port: 9300

node.master: {{ is_master_node }}
node.name: {{ node_name }}

path:
  logs: /var/log/elasticsearch
  data: /var/lib/elasticsearch

discovery:
  zen:
    ping.unicast.hosts: [ &#39;{{ hostvars[&#39;elasticsearchNode1&#39;][&#39;ansible_facts&#39;][&#39;all_ipv4_addresses&#39;] | last }}:9300&#39;, &#39;{{ hostvars[&#39;elasticsearchNode2&#39;][&#39;ansible_facts&#39;][&#39;all_ipv4_addresses&#39;] | last }}:9300&#39;, &#39;{{ hostvars[&#39;elasticsearchNode3&#39;][&#39;ansible_facts&#39;][&#39;all_ipv4_addresses&#39;] | last }}:9300&#39; ]
    minimum_master_nodes: 2

```

The most critical parts (the parts that make the cluster work together) are the network.publish\_host value, which _must be unique_, and the discovery.zen.ping.unicast.hosts value, which must contain the locations that any member of the cluster can find other members (looking at the transport.tcp.port value for which port to look at). If there are multiple IP addresses on the box you&#39;re putting elasticsearch on (e.g. 10.0.0.1 and 192.56.168.101), then the node will fail to start unless you explicitly tell elasticsearch which publish\_host you want it to advertise itself on. It can bind to multiple public hosts, but only publish itself to one.

With the above configured, you should be able to run:

```bash
$ molecule create &amp;&amp; molecule converge
```

And, eventually, the cluster should come up and sync with each other. If you hit [http://192.168.56.101:9200](http://192.168.56.101:9200), [http://192.168.56.102:9200](http://192.168.56.102:9200,), or [http://192.168.56.103:9200](http://192.168.56.103:9200), you should see the same cluster\_uuid in each case, letting you know that they are working together.
