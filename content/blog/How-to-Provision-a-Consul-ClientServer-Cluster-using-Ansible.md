---
title: "How to Provision a Consul Client-Server Cluster using Ansible"
date: 2019-04-27T21:15:18
draft: false
tags: [distributed systems, vagrant, ansible, DevOps, molecule, consul]
---

The source code for this blog post can be found [on GitHub](https://github.com/nfisher23/some-ansible-examples/tree/master/consul-server).

[Consul](https://www.consul.io) can run in either client or server mode. As far as Consul is concerned, the primary difference between client and server mode are that Consul Servers participate in the consensus quorum, store cluster state, and handle queries. Consul Agents are often deployed to act as middle-men between the services and the Consul Servers, which need to be highly available by design.

Ignoring my opinion about the architecture choices, we will expand on the last post ( [How to Provision a Standalone Consul Server with Ansible](https://nickolasfisher.com/blog/how-to-provision-a-standalone-consul-server-with-ansible)) and modify our ansible role to allow for agents to join the standalone consul server.

Because [the default Restart=Always behavior of systemd isn't automatically honored](https://unix.stackexchange.com/questions/289629/systemd-restart-always-is-not-honored), and we will need for the Consul Agents to restart while they try to connect to the server (which could still be coming up), the first thing we will do is get our Consul systemd service to keep trying to restart ad infinitum. Modify our **templates/consul.service.j2** file to look like:

```
[Unit]
Description=solo consul server example

[Service]
WorkingDirectory={{ consul_config_dir }}
User=root
ExecStart={{ consul_install_dir }}/consul agent -config-dir={{ consul_config_dir }}
Restart=Always
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
```

Because the Consul Client and Consul Server instances will be on different virtual machines, we will need to add one for the Consul Client in our **molecule/default/molecule.yml** file:

```yaml
---
dependency:
  name: galaxy
driver:
  name: vagrant
  provider:
    name: virtualbox
lint:
  name: yamllint
platforms:
  - name: consulServer
    box: ubuntu/xenial64
    memory: 2048
    provider_raw_config_args:
    - "customize ['modifyvm', :id, '--uartmode1', 'disconnected']"
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.211
      type: static
  - name: consulClient
    box: ubuntu/xenial64
    memory: 2048
    provider_raw_config_args:
    - "customize ['modifyvm', :id, '--uartmode1', 'disconnected']"
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.212
      type: static
provisioner:
  name: ansible
  inventory:
    host_vars:
      consulClient:
        is_server: "false"
        node_name: client
      consulServer:
        is_server: "true"
        node_name: server
  lint:
    name: ansible-lint
scenario:
  name: default
verifier:
  name: testinfra
  lint:
    name: flake8
```

The two main things that we have done here are:

- Added a virtual machine, called consulClient﻿
- Set two host variables for both the consulClient and consulServer virtual machines. We will use them in our next step.

As luck would have it, we do not need to make any changes to the tasks/main.yml file. The only thing left to make this playbook "just work" is to modify the **templates/consul.config.j2** file to look like:

```json
{
    "node_name": "{{ node_name }}",
    "addresses": {
        "http": "{{ ansible_facts['all_ipv4_addresses'] | last }} 127.0.0.1"
    },
    "server": {{ is_server }},
    "advertise_addr": "{{ ansible_facts['all_ipv4_addresses'] | last }}",
    "client_addr": "127.0.0.1 {{ ansible_facts['all_ipv4_addresses'] | last }}",
    "connect": {
        "enabled": true
    },
    "data_dir": "{{ consul_data_dir }}",
{% if is_server == 'false' %}
    "start_join": [ "{{ hostvars['consulServer']['ansible_all_ipv4_addresses'] | last }}"]
{% else %}
    "bootstrap": true
{% endif %}
}
```

If we are running in server mode, we need the up and coming standalone server to bootstrap itself, hence **"bootstrap": true**. If, instead, we are running in client mode, we need the client to find our server to register with. Since molecule automatically adds inventory based on what is defined in the platforms section, we can reference our consul server's IP address in start\_join.

If you run:

```bash
$ molecule create &amp;&amp; molecule converge
```

You should be able to hit [http://192.168.56.211:8500/v1/agent/members](http://192.168.56.211:8500/v1/agent/members,) and see both the consul server and the consul client connected.

Be sure to [go get the source code](https://github.com/nfisher23/some-ansible-examples/tree/master/consul-server) so you can play around with this yourself.
