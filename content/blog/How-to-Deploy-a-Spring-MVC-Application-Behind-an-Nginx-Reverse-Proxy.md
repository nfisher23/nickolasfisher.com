---
title: "How to Deploy a Spring MVC Application Behind an Nginx Reverse Proxy"
date: 2019-04-06T14:44:50
draft: false
tags: [java, ngnix, vagrant, ansible, spring, DevOps, maven]
---

[Nginx](https://www.nginx.com/) is a popular webserver, excellent at serving up static content, and commonly used as a load balancer or reverse proxy. This post will set up a basic [Spring Boot](https://spring.io/projects/spring-boot) MVC web application, and use Nginx as a reverse proxy. The source code can be found [on GitHub](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx).

### What is a Reverse Proxy?

A reverse proxy is the middle-man between the consumer of your service/application and the application itself. Take, for example, somebody typing your web domain (https://your-awesome-domain.com) into her browser. After the browser finds the IP address of where your web domain is located, her browser sends an HTTP request to the browser at the specified endpoint. If you _don't_ have a reverse proxy set up, then your application will have to be listening for active connections at your-awesome-domain.com:443, and be capable of serving up a CA-signed certificate along with the response. If your site doesn't have https configured, then it must be listening at port 80 (and obviously would not need any certs).

This is fine for some applications. However, what if you want to put another web app on the same VM (because you're cheap, like me)? With this setup, you're going to need something in between your web applications to decide which one to forward the request to. That "something" is a reverse proxy. The person deciding to come to your site still enters https://your-awesome-domain.com into the browser. Before, her signal would look like: \[her\] -> \[your web app\]. Now, her request signal looks like \[her\] -> \[reverse proxy\] -> \[your web app\].

Common reasons for reverse proxies include making zero downtime deployments much easier to do, handling certificate management for https-enabled sites, cramming as many web apps on your server as the thing can handle, or selectively caching content--which I will cover in the next post.

### Create an Ansible Role

I will use [Ansible](https://www.ansible.com/) to provision the server for this example. You will need ansible, molecule, vagrant, and virtual box on your machine to follow along.

Navigate to the directory that you want this project to go into and type:

```bash
$ molecule init role -r reverse-proxy-nginx -d vagrant
```

I'm using vagrant as the VM provider here, and the ansible role I'm creating is called "reverse-proxy-nginx." Modify the **molecule/default/molecule.yml** file's **providers** section to the following:

```yaml
platforms:
  - name: reverse-proxy
    box: ubuntu/xenial64
    memory: 1024
    provider_raw_config_args:
    - "customize ['modifyvm', :id, '--uartmode1', 'disconnected']"
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.202
      type: static

```

The first thing we will need is a Spring MVC application to work with. For simplicity, we're going to keep the app source code within this ansible role. In a real application, you should set up a CI/CD pipeline that the application would go through, but I'm going to keep the focus on getting a working example. Create a **app/** directory, then go to the [spring initializer](https://start.spring.io/) and select the "Web" dependency option, then Maven as the build engine. Place the generated code inside the **app/** directory.

We can then add a **SimpleController.java** class to the **app/src/main/java/com/nickolasfisher/simplemvc/** directory that is, well, simple:

```java
package com.nickolasfisher.simplemvc;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class SimpleController {

    @GetMapping("/**")
    public ResponseEntity<String> simpleResponder() {
        return new ResponseEntity<>("<h1>Welcome to my site!</h1>", HttpStatus.ACCEPTED);
    }
}

```

On the server, we are going to need Java and Nginx. In the [source code for this post](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx), I've included two separate roles called **openjdk** and **nginx**. The ansible role that gets Java looks like:

```yaml
---
- name: Get Java tarball
  get_url:
    url: "{{ jdk_url }}"
    dest: /etc/{{ jdk_tarball }}
  become: yes

- name: make java directory
  file:
    path: "/usr/lib/openjdk-{{ jdk_version }}"
    state: directory
  become: yes

- name: unpack tarball
  unarchive:
    dest: "/usr/lib/openjdk-{{ jdk_version }}/"
    src: /etc/{{ jdk_tarball }}
    remote_src: yes
  become: yes

- name: update alternatives for java
  alternatives:
    name: java
    path: "/usr/lib/openjdk-{{ jdk_version }}/jdk-{{ jdk_version }}/bin/java"
    link: /usr/bin/java
    priority: 2000
  become: yes

- name: set java environment variable
  blockinfile:
    insertafter: EOF
    path: /etc/environment
    block: export JAVA_HOME=/usr/lib/openjdk-{{ jdk_version }}/jdk-{{ jdk_version }}
  become: yes

- name: re-source env variables
  shell: . /etc/environment
  become: yes

```

Where the variables are:

```yaml
---
# vars file for openjdk
jdk_version: 11.0.2
jdk_tarball: openjdk-{{ jdk_version }}_linux-x64_bin.tar.gz
jdk_url: "https://download.java.net/java/GA/jdk11/9/GPL/{{ jdk_tarball }}"

```

The Nginx role playbook looks like:

```yaml
---
# tasks file for nginx
- name: install nginx
  apt:
    name: nginx
    update_cache: yes
  become: true

- name: install nginx conf file
  template:
    dest: /etc/nginx/sites-available/{{ site_alias }}.conf
    src: server.conf.j2
  become: yes

- name: link nginx conf file
  file:
    src: /etc/nginx/sites-available/{{ site_alias }}.conf
    dest: /etc/nginx/sites-enabled/{{ site_alias }}.conf
    state: link
  become: yes

- name: remove nginx defaults
  file:
    path: "{{ item }}"
    state: absent
  with_items:
    - /etc/nginx/sites-available/default
    - /etc/nginx/sites-enabled/default
  become: yes
  when: remove_nginx_defaults

- name: reload nginx
  command: nginx -s reload
  become: yes

```

With variables like:

```yaml
---
# vars file for nginx
app_port: 8080
site_alias: my-site
remove_nginx_defaults: true

```

We also use a Jinja2 template for the configuration file, which is very simple (inside **templates/server.conf.j2**):

```
server {
    location / {
        proxy_pass http://localhost:{{ app_port }};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $http_host;
        proxy_cache_bypass $http_upgrade;
    }
}

```

This nginx conf file is where you can insert all of the middle-man logic that you want. in this case, we set a few headers and the http version. But we can easily [add TLS management with certbot](https://www.digitalocean.com/community/tutorials/how-to-set-up-let-s-encrypt-with-nginx-server-blocks-on-ubuntu-16-04) if we so choose.

Back inside our **reverse-proxy-nginx** role, we need to add these roles as dependencies in the **meta/main.yml** file:

```yaml
---
dependencies:
  - role: openjdk
  - role: nginx
```

We can now move on to the logic of deploying it. Again, in a production setup, we would want an automated CI/CD pipeline to handle deployments, preferably only deploying a release branch. However, for this simple example, we will build it using ansible and send up the artifact directly. The only protection that this offers is building and running the unit tests, but configuration management basically doesn't exist.

Note that you will need maven installed on your system for this to run properly.

We need to get the jar artifact on the server, then create a systemd service file that will run it for us. In the **reverse-proxy-nginx/tasks/main.yml**:

```yaml
---
# tasks file for reverse-proxy-nginx
- name: ensure files dir empty
  file:
    path: ../../files/{{ jar_name }}
    state: absent
  delegate_to: localhost

- name: build solution and move jar to files
  shell: pwd &amp;&amp; cd ../../app &amp;&amp; mvn clean install &amp;&amp; cp target/*.jar ../files/{{ jar_name }}
  delegate_to: localhost

- name: ensure apps dir exists
  file:
    path: "{{ jar_dir }}"
    state: directory
    mode: 0755
  become: yes

- name: send jar
  copy:
    src: "{{ jar_name }}"
    dest: "{{ path_to_jar }}"
    mode: 0755
    force: yes
  become: yes
  notify: restart app

- name: setup service file
  template:
    src: app.service.j2
    dest: /etc/systemd/system/app.service
  become: yes
  notify: restart app

```

We will need a Jinja2 template for systemd in **templates/app.service.j2:**

```
[Unit]
Description=slow server to demonstrate caching

[Service]
WorkingDirectory={{ jar_dir }}
ExecStart=/usr/bin/java -jar {{ path_to_jar }}
Restart=always

[Install]
WantedBy=multi-user.target

```

And variables in **vars/main.yml**:

```yaml
---
# vars file for reverse-proxy-nginx
jar_dir: /opt/apps/app
jar_name: app.jar
path_to_jar: "{{ jar_dir }}/{{ jar_name }}"

```

Finally, we need to set up a handler in the **handlers/main.yml** to restart the app when we send it up:

```yaml
---
# handlers file for reverse-proxy-nginx
- name: restart app
  systemd:
    name: app.service
    daemon_reload: yes
    state: restarted
  become: yes

```

You should now be able to run:

```bash
$ molecule create &amp;&amp; molecule converge
```

And see the VM come up at [http://192.168.56.202.](http://192.168.56.202.)

Definitely go [check out the source code](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx) to see this in action.
