---
title: "How to do a Rolling Upgrade of Multiple Logstash Instances Using Ansible"
date: 2019-03-17T23:27:43
draft: false
---

You can see the source code for this post [on GitHub](https://github.com/nfisher23/some-ansible-examples).

In a previous post on [How to Provision Multiple Logstash Hosts Using Ansible](https://nickolasfisher.com/blog/How-to-Provision-Multiple-Logstash-Hosts-Using-Ansible), we saw that provisioning logstash is pretty straightforward. However, what do we do with it after it&#39;s been out there transforming messages this entire time? Given that elastic comes out with a new version of Logstash every fifteen or twenty minutes, a wise person would look to automate the upgrade process as soon as possible.

This post will examine an in place upgrade of logstash.

### Create an Ansible Role

We can create out ansible role using Molecule, and use vagrant as our local virtual machine provider:

```bash
$ molecule init role -r upgrade-logstash -d vagrant
```

First, we&#39;ll need to adjust our **molecule/default/molecule.yml** file by creating some virtual machine to drop our logstash instances on:

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

We can then include our work from the previous post on provisioning logstash to first ensure that we have a logstash instance to upgrade. We can simply include it as a dependency and let ansible find it (note: you will either have to have your directory structure like the samples on github or you will need to configure ansible to look for the appropriate roles). Modify your **meta/main.yml** file to look like

```yaml
---
dependencies:
  - role: install-logstash
```

At this point, you should be able to run

```bash
$ molecule create &amp;&amp; molecule converge
```

To get your VMs up and logstash on them.

We will create a logstash upgrade yml file and only use it when we have a parameter upgrade\_ls set to true. I&#39;m dropping this file in **tasks/upgrade\_ls.yml:**

```yaml
---
- name: ensure logstash already present
  service:
    name: logstash
    state: started
  become: yes

- name: upgrade as root
  block:
  - name: get logstash deb version
    get_url:
      dest: &#34;/etc/{{ ls_version_to_upgrade_to }}&#34;
      url: &#34;https://artifacts.elastic.co/downloads/logstash/{{ ls_version_to_upgrade_to }}&#34;
      checksum: &#34;sha512:https://artifacts.elastic.co/downloads/logstash/{{ ls_version_to_upgrade_to }}.sha512&#34;
    become: yes

  - name: shut down instance
    service:
      name: logstash
      state: stopped

  - name: install new version
    apt:
      deb: &#34;/etc/{{ ls_version_to_upgrade_to }}&#34;

  - name: test configuration files
    shell: /usr/share/logstash/bin/logstash -t &#34;--path.settings&#34; &#34;/etc/logstash&#34;

  - name: restart pipeline
    service:
      name: logstash
      state: started

  - name: wait for logstash to come up
    wait_for:
      host: 127.0.0.1
      port: 9600
      delay: 5

  become: yes

```

This can then be invoked in the **tasks/main.yml** file by adjusting it like so:

```yaml
---
# tasks file for upgrade-logstash
- include: upgrade_ls.yml
  when: upgrade_ls

```

We will then adjust our provisioner section in the **molecule/default/molecule.yml** file to look like:

```yaml
provisioner:
  name: ansible
  inventory:
    host_vars:
      lsNode1:
        upgrade_ls: true
        ls_version_to_upgrade_to: logstash-6.5.3.deb
      lsNode2:
        upgrade_ls: true
        ls_version_to_upgrade_to: logstash-6.5.3.deb

```

As you can see, we will be upgrade logstash to version 6.5.3 in this example.

Finally, we will want to upgrade one at a time, which means that we&#39;ll use the serial flag in our **molecule/default/playbook.yml**:

```yaml
---
- name: Converge
  hosts: all
  serial: 1
  roles:
    - role: upgrade-logstash

```

At this point, you should be able to run:

```bash
$ molecule converge
```

And see it upgrade one, wait for it to come up, then upgrade the other one.

Definitely go [see the source code on GitHub](https://github.com/nfisher23/some-ansible-examples) to get your hands on this example.
