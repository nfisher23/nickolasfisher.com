---
title: "How To Create a Digital Ocean Droplet and Provision It Using Ansible"
date: 2019-06-15T20:40:48
draft: false
tags: [distributed systems, ansible, DevOps, digital ocean]
---

Ansible allows you to provision servers in an idempotent fashion. It lets you see the state of your VM configuration as it resides in code, which is light years better than the sysadmin ways of yesterday.

The digital ocean ansible module also lets you use ansible to declare the actual virtual machines that you want to exist. Done correctly, this can also be idempotent, and elevates Ansible to being closer to an orchestration framework.

**Note**: There are, as of this writing, two digital ocean modules in ansible that can get the job done. The [deprecated digital\_ocean module](https://docs.ansible.com/ansible/latest/modules/digital_ocean_module.html) and the [digital\_ocean\_droplet ansible module](https://docs.ansible.com/ansible/latest/modules/digital_ocean_droplet_module.html#digital-ocean-droplet-module). The supported module is only available from Ansible 2.8 onwards, so if upgrading is not an option at this time, then you&#39;ll have to use the deprecated version. I&#39;ll include some of the differences below.

To get started, make sure you [create your own digital ocean api token](https://www.digitalocean.com/docs/api/create-personal-access-token/).

### Creating a Droplet in Code

To create a droplet, take your digital ocean api token and set an environment variable for this shell session:

```bash
$ export DO_API_TOKEN=abcdefghijklmnop123456
```

Now navigate to the directory that you want this playbook to reside in and create an empty file:

```bash
$ touch create_droplet_sample.yml
```

If you running ansible 2.8 or greater, we can create a droplet, add a tag, then add the host to a &#34;do&#34; host group like so:

```yaml
---
- hosts: localhost
  connection: local
  gather_facts: false

  # run:
  # $ export DO_API_TOKEN=your-token
  # then run this playbook to create droplet
  tasks:
    - digital_ocean_droplet:
        unique_name: yes # &#34;yes&#34; makes it idempotent
        region: ams3 # slug of the region you would like your server to be created in.
        image: ubuntu-18-10-x64 # slug of the image you would like the droplet created with.
        wait: yes
        name: &#34;new-tmp-droplet&#34; # name of the droplet
        size_id: s-1vcpu-1gb # slug of the size you would like the droplet created with.
        state: present
        ssh_keys: [ &#39;0123456789&#39; ] # &lt;----- put your numeric SSH key in here
      register: created_droplet

    - digital_ocean_tag:
        name: some-sample-tag
        resource_id: &#34;{{ created_droplet.data.droplet.id }}&#34;
        state: present
      register: tag_response

    - name: add hosts
      add_host:
        name: &#34;{{ created_droplet.data.ip_address }}&#34;
        groups: &#34;do&#34;

```

This uses the digital\_ocean\_droplet module to create a droplet only if it doesn&#39;t exist. We then register the response from the operation to a **created\_droplet** variable, and use that variable to add a custom tag to the droplet. We finally add the ip address of the created droplet to our dynamic inventory, which we will use shortly.

**Note**: if you want to use this sample code, you&#39;ll have to have your DO\_API\_TOKEN environment variable defined, and you&#39;ll also have to use your own numeric SSH key in the **ssh\_keys** argument in the above module.

If you running an ansible version &lt; 2.8, you&#39;re playbook would look something like this instead:

```yaml
---
- hosts: localhost
  connection: local
  gather_facts: false

  # run:
  # $ export DO_API_TOKEN=your-token
  # then run this playbook to create droplet
  # then run this playbook to create droplet
  tasks:
    - name: create droplet
      digital_ocean:
        unique_name: yes
        region_id: ams3
        image_id: ubuntu-18-10-x64
        wait_timeout: 100
        wait: yes
        name: &#34;new-tmp-droplet&#34;
        size_id: s-1vcpu-1gb
        state: present
        command: droplet
        ssh_key_ids: [ &#39;0123456789&#39; ] # &lt;---- remember to put your SSH key here
      register: created_droplet

    - digital_ocean_tag:
        name: some-sample-tag
        resource_id: &#34;{{ created_droplet.droplet.id }}&#34;
        state: present # not required. choices: present;absent. Whether the tag should be present or absent on the resource.
      register: tag_response

    - name: add hosts
      add_host:
        name: &#34;{{ created_droplet.droplet.ip_address }}&#34;
        groups: &#34;do&#34;

```

There are a few differences in children of the digital\_ocean module, and you&#39;ll have to make sure you understand the registered response, because the structure changes quite a bit.

To prove that it works properly, we&#39;ll deploy a simple static nginx server that returns a custom index page. The next part of the playbook is the same regardless of your ansible version:

```yaml
....

- hosts: do
  remote_user: root
  gather_facts: no

  vars:
    ansible_python_interpreter: /usr/bin/python3

  tasks:
    - name: wait for port 22 to become available
      wait_for:
        host: &#34;{{ inventory_hostname }}&#34;
        port: 22
      delegate_to: localhost

    - name: gather facts now that host is available
      setup:

    - name: install nginx
      apt:
        name: nginx

    - name: modify html file
      copy:
        src: ./index.html
        dest: /var/www/html/index.html

```

In the same directory, we&#39;ll place our custom index.html file with the following contents:

```html
&lt;h1&gt;You made it&lt;/h1&gt;
&lt;p&gt;This should show up instead of nginx home page&lt;/p&gt;

```

If you navigate to the IP address of the created droplet, you should see that page displayed.

Note that you will have to type &#34;yes&#34;, by default, when prompted to connect to the newly created droplet. If you don&#39;t want to type &#34;yes&#34; in the middle of your ansible playbook, include an **ansible.cfg** file in the same directory as your playbook that has this:

```
[defaults]
host_key_checking = False
```
