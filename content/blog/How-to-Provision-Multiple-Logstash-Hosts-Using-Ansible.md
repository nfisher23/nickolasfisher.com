---
title: "How to Provision Multiple Logstash Hosts Using Ansible"
date: 2019-03-06T23:33:35
draft: false
tags: [distributed systems, vagrant, ansible, the elastic stack, DevOps]
---

The source code for this post can be found [on GitHub](https://github.com/nfisher23/some-ansible-examples).

[Logstash](https://www.elastic.co/products/logstash) primarily exists to extract useful information out of plain-text logs. Most applications have custom logs which are in whatever format the person writing them thought would look reasonable...usually to a human, and not to a machine. While countless future developer hours would be preserved if everything were just in JSON, that is sadly not even remotely the case, and in particular it&#39;s not the case for log files. Logstash aims to be the intermediary between the various log formats and Elasticsearch, which is the document database provided by Elastic as well.

This post will focus on writing an ansible playbook to provision two logstash hosts, each of which will receive logs from a beats input and forward the output to an elasticsearch cluster. See a previous post on [how to provision an elasticsearch cluster using ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Multi-Node-Elasticsearch-Cluster-Using-Ansible).

### Create the Ansible Role

Navigate to the directory you want to keep this ansible role and type:

```bash
$ molecule init role -d vagrant -r install-logstash
```

I&#39;m choosing to use vagrant as a local VM provider and I&#39;m calling this role install-logstash.

Since we want to demonstrate multiple nodes, we&#39;ll adjust our **molecule/default/molecule.yml** file&#39;s _platforms_ section to look like this:

```yaml
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

```bash
$ molecule create
```

Will give you the two virtual machines outlined above.

I&#39;ll jump ahead here and set up a variable we&#39;re going to use in our playbook, which is the logstash version in a deb file that we&#39;re going to use:

```yaml
# vars file for install-logstash
logstash_deb_file: logstash-6.4.0.deb

```

Because I want this to be compatible with the post on [installing a multi-node elasticsearch cluster,](https://nickolasfisher.com/blog/How-to-Provision-a-Multi-Node-Elasticsearch-Cluster-Using-Ansible) I&#39;m electing to use logstash version 6.4.0.

We can setup our **tasks/main.yml** file to perform the necessary steps in an idempotent way. These are pretty straightforward:

```yaml
---
# tasks file for install-logstash
- name: ensure Java is installed
  apt:
    name: &#34;openjdk-8-jdk&#34;
    state: present
    update_cache: yes
  become: yes

- name: download deb package
  get_url:
    dest: &#34;/etc/{{ logstash_deb_file }}&#34;
    url: &#34;https://artifacts.elastic.co/downloads/logstash/{{ logstash_deb_file }}&#34;
    checksum: &#34;sha512:https://artifacts.elastic.co/downloads/logstash/{{ logstash_deb_file }}.sha512&#34;
  become: yes

- name: install from deb package
  apt:
    deb: &#34;/etc/{{ logstash_deb_file }}&#34;
  become: yes
  notify: restart logstash

- name: setup conf filter
  template:
    dest: /etc/logstash/conf.d/my-pipeline.conf
    src: my-pipeline.conf.j2
    force: yes
    mode: 0644
  become: yes
  notify: restart logstash

```

We use the logstash\_deb\_file variable liberally here, as you can see. We need java installed for logstash, and while I&#39;d like to use Java 11, the Elastic Stack has been relatively slow in upgrading their code base to be supportive of it, so Java 8 is what it is for now. We then simply get and install logstash via the deb file, and move a jinja2 template (about to show you that one) into the **conf.d** folder so logstash can give us some pipelines to work with.

In the **templates** folder, create a file called **my-pipeline.conf.j2** and fill it with:

```json
input {
  beats {
    host =&gt; &#34;{{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }}&#34;
    port =&gt; &#34;5044&#34;
  }
}
filter {

}
output {
  elasticsearch {
    hosts =&gt; [&#34;192.168.56.101:9200&#34;, &#34;192.168.56.102:9200&#34;, &#34;192.168.56.103:9200&#34;]
  }
}

```

This simple pipeline grabs the last IP address defined on our ansible host (192.168.56.111 for lsNode1) and sets up a listener on port 5044 to collect input from beats. There are no filters defined, and it will just pass any messages it gets straight onto an elasticsearch cluster.

I&#39;ve hardcoded three addresses for elasticsearch here. To make this more extensible, those should be externalized to variables and eventually pulled out of your inventory file.

You will also need a handler in the **handlers/main.yml** file:

```yaml
---
# handlers file for install-logstash
- name: restart logstash
  service:
    name: logstash
    state: restarted
  become: yes

```

You should, at this point, be able to run:

```bash
$ molecule converge
```

And see the logstash instances come up without issue.

Be sure to [pull down the GitHub code](https://github.com/nfisher23/some-ansible-examples) if you get stuck somewhere.
