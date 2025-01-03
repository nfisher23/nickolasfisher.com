---
title: "How to Run a Script on Cluster State Change Using Consul Watch"
date: 2019-05-01T00:00:00
draft: false
---

You can see the sample code for this post [on Github](https://github.com/nfisher23/some-ansible-examples/tree/master/consul-server).

[Consul Watches](https://www.consul.io/docs/agent/watches.html) offer a way to hook into changes to the Consul cluster state at runtime.The specific type of changes we will be looking at hooking into in this post are [checks](https://www.consul.io/docs/agent/watches.html#type-checks). Whenever a node or service comes online and registers to Consul, whenever an existing node or service leaves Consul, or whenever an existing node or service becomes unresponsive, Consul will emit a check event. This check event can invoke a process to monitor the health of our services, alerting human being that action might soon be necessary.

There are two ways to provide custom logic on an emitted check event: either run a script or have Consul call an HTTP endpoint. Running a script will require Consul to be able to to reach the script and have permissions to execute it, whereas calling an HTTP endpoint just requires that something is listening on the appropriate IP and port. However, the downside of an HTTP endpoint is that the service listening on it can&#39;t be down. This is a classic &#34;who watches the watchmen?&#34; problem. If we have monitoring logic that we rely on for all of our services, what is going to monitor the service that monitors?

That reason is why I prefer the script approach, and I&#39;ll show you how to accomplish this using Ansible.

### Deploy a Local Cluster

In a previous post, I showed you [how to provision a Consul client-server cluster using Ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Consul-ClientServer-Cluster-using-Ansible). Starting from that point on, we can make some sensible modifications to POC this functionality.

First, we&#39;ll need a basic script to invoke. Create a **files/watch\_script.py** script and fill it with:

```
#!/usr/bin/python3

with open(&#39;somefile.txt&#39;, &#39;a&#39;) as file:
    file.write(&#39;some new line\n&#39;)
```

Like all python scripts, this reads pretty much like English, and we can see that we are writing &#34;some new line&#34; to a file in the same directory as the script, and we&#39;re calling the file &#34;somefile.txt&#34;.

Next, we&#39;ll need to drop the script on the server where Consul is provisioned. Insert the following line in the **tasks/main.yml** file:

``` yaml
- name: send consul watch script
  copy:
    dest: &#34;{{ consul_config_dir }}/watch_script.py&#34;
    src: watch_script.py
    mode: 0777 # restrict this mode more in production
    owner: root
  become: yes

```

This is just a POC, but you will want to lock down the script to be owned by Consul in a production environment, and you will also want to put it in a different directory than the configuration directory.

Finally, adjust your **templates/consul.config.j2** file to look like:

``` json
{
    &#34;node_name&#34;: &#34;{{ node_name }}&#34;,
    &#34;addresses&#34;: {
        &#34;http&#34;: &#34;{{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }} 127.0.0.1&#34;
    },
    &#34;server&#34;: {{ is_server }},
    &#34;advertise_addr&#34;: &#34;{{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }}&#34;,
    &#34;client_addr&#34;: &#34;127.0.0.1 {{ ansible_facts[&#39;all_ipv4_addresses&#39;] | last }}&#34;,
    &#34;connect&#34;: {
        &#34;enabled&#34;: true
    },
    &#34;data_dir&#34;: &#34;{{ consul_data_dir }}&#34;,
    &#34;watches&#34;: [
        {
            &#34;type&#34;: &#34;checks&#34;,
            &#34;handler&#34;: &#34;{{ consul_config_dir }}/watch_script.py&#34;
        }
    ],
{% if is_server == &#39;false&#39; %}
    &#34;start_join&#34;: [ &#34;{{ hostvars[&#39;consulServer&#39;][&#39;ansible_all_ipv4_addresses&#39;] | last }}&#34;]
{% else %}
    &#34;bootstrap&#34;: true
{% endif %}
}
```

The critical part of this is the &#34;watches&#34; section, which will be rendered by Jinja2 as:

``` json
    &#34;watches&#34;: [
        {
            &#34;type&#34;: &#34;checks&#34;,
            &#34;handler&#34;: &#34;/etc/consul/watch_script.py&#34;
        }
    ],
```

Which tells Consul that, whenever there is a state changes related to nodes or services, to invoke the script at the handler path.

If you run:

``` bash
$ molecule create &amp;&amp; molecule converge
```

At this point, you will see the cluster come up. To prove that the file gets created and populated by our script, you can either restart one of the Consul Agents, or refer to a previous post on [registering a simple java service to a consul cluster](https://nickolasfisher.com/blog/How-to-Register-a-Spring-Boot-Service-to-a-Consul-Cluster). Either one will demo the functionality provided.


