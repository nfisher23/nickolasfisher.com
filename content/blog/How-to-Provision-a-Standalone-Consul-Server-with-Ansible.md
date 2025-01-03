---
title: "How to Provision a Standalone Consul Server with Ansible"
date: 2019-04-27T19:49:14
draft: false
---

You can find the source code for this post [on GitHub](https://github.com/nfisher23/some-ansible-examples/tree/master/consul-server).

[Consul](https://www.consul.io/) is a distributed service discovery engine. It&#39;s primary purpose is to track and manage services that interact with it--usually via an HTTP API. It monitors the health of services in near real time, providing a more robust way of routing services to healthy and responsive nodes.

In this post, we&#39;ll look at provisioning a standalone consul server with Ansible. This is not recommended for production, both because this Consul Server is a single point of failure and because there is no security in this example, but it is a good starting place to Proof-of-Concept the technology.

You will need Molecule, Ansible, VirtualBox, and Vagrant for this example to work. It will be easier for you to follow along if you are already familiar with those tools.

### Create the Ansible Role

Start by running:

```bash
$ molecule init role -r consul-server -d vagrant
```

This creates a new Ansible role, wrapping Molecule around it, and chooses Vagrant as the VM driver.

Consul is written using Golang--a huge draw of Golang is that it is almost always compiled ahead-of-time, to a binary executable of the target machine. To get consul to run on our machine, then, it suffices for us to figure out what the OS of that machine will be. In this example, we are using Ubuntu, which is a Linux distribution, and we can thus install consul\_(version)\_linux\_amd64.zip (see the [Consul Downloads](https://www.consul.io/downloads.html) page for any other distributions).

In your ansible role, modify your **vars/main.yml** file to look like:

```yaml
---
# vars file for consul-server
consul_version: 1.4.2
consul_zip_file: consul_{{ consul_version }}_linux_amd64.zip
consul_install_dir: /usr/local/bin
consul_config_dir: /etc/consul
consul_data_dir: /var/data
```

We will need all of these in a moment, they are all pretty self explanatory.

While you can technically pass in a large collection of configuration parameters to consul at startup time, it is much more manageable to pass in a configuration file using [-config-dir or -config-file](https://www.consul.io/docs/agent/options.html#_config_file)--for this example, we will do exactly that. Our Jinja2 template for our consul configuration file can go in **templates/consul.config.j2** and look like:

```json
{
    &#34;node_name&#34;: &#34;example&#34;,
    &#34;addresses&#34;: {
        &#34;http&#34;: &#34;{{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }} 127.0.0.1&#34;
    },
    &#34;server&#34;: true,
    &#34;advertise_addr&#34;: &#34;{{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }}&#34;,
    &#34;client_addr&#34;: &#34;127.0.0.1 {{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }}&#34;,
    &#34;connect&#34;: {
        &#34;enabled&#34;: true
    },
    &#34;data_dir&#34;: &#34;{{ consul_data_dir }}&#34;,
    &#34;bootstrap&#34;: true
}
```

This tells Consul to run in Server Mode, and to bootstrap itself on startup. It also specifies the IP of the target machine using ansible\_facts, and specifies the data directory with data\_dir.

We can now move forward with the template for our Systemd service. In your **templates/consul.service.j2** file:

```
[Unit]
Description=solo consul server example

[Service]
WorkingDirectory={{ consul_config_dir }}
User=root
ExecStart={{ consul_install_dir }}/consul agent -config-dir={{ consul_config_dir }}

[Install]
WantedBy=multi-user.target

```

This is very simple: the user running this process is root, and we are using configuration parameters from our vars/main.yml file to generate this file on the fly.

We need two more things for this role to be complete. The first is an Ansible handler to restart consul when we make critical changes that require a restart. In **handlers/main.yml**:

```yaml
---
# handlers file for consul-server
- name: restart consul
  systemd:
    name: consul.service
    daemon_reload: yes
    state: restarted
  become: yes
```

Finally, we can specify the tasks that are going to carry out the installation for us. In **tasks/main.yml**:

```yaml
---
# tasks file for consul-server
- name: get consul zip
  get_url:
    dest: &#34;/etc/{{ consul_zip_file }}&#34;
    url: &#34;https://releases.hashicorp.com/consul/{{ consul_version }}/{{ consul_zip_file }}&#34;
  become: yes

- name: ensure unzip present
  apt:
    name: unzip
    update_cache: yes
  become: yes

- name: place unzipped consul on path
  unarchive:
    src: &#34;/etc/{{ consul_zip_file }}&#34;
    dest: &#34;{{ consul_install_dir }}&#34;
    remote_src: yes
  become: yes

- name: ensure directories for data and config exists
  file:
    path: &#34;{{ item }}&#34;
    state: directory
  with_items:
    - &#34;{{ consul_config_dir }}&#34;
    - &#34;{{ consul_data_dir }}&#34;
  become: yes

- name: send consul configuration file
  template:
    dest: &#34;{{ consul_config_dir }}/config.json&#34;
    src: consul.config.j2
  notify: restart consul
  become: yes

- name: ensure consul service file exists
  template:
    dest: /etc/systemd/system/consul.service
    src: consul.service.j2
    force: yes
    mode: 0644
  notify: restart consul
  become: yes
```

The critical steps here are: downloading consul, placing the unzipped binary on the path, ensuring configuration and systemd template files are up there in their appropriate location. We let the handler start Consul up for us.

Once you run:

```bash
$ molecule create &amp;&amp; molecule converge
```

And the virtual machine comes up, you should be able to hit 192.168.56.211:8500, and see ﻿Consul Agent﻿ come up.
