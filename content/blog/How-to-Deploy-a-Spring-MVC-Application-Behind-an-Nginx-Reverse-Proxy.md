---
title: "How to Deploy a Spring MVC Application Behind an Nginx Reverse Proxy"
date: 2019-04-01T00:00:00
draft: false
---

[Nginx](https://www.nginx.com/) is a popular webserver, excellent at serving up static content, and commonly used as a load balancer or reverse proxy. This post will set up a basic [Spring Boot](https://spring.io/projects/spring-boot) MVC web application, and use Nginx as a reverse proxy. The source code can be found [on GitHub](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx).

### What is a Reverse Proxy?

A reverse proxy is the middle-man between the consumer of your service/application and the application itself. Take, for example, somebody typing your web domain (https://your-awesome-domain.com) into her browser. After the browser finds the IP address of where your web domain is located, her browser sends an HTTP request to the browser at the specified endpoint. If you _don&#39;t_ have a reverse proxy set up, then your application will have to be listening for active connections at your-awesome-domain.com:443, and be capable of serving up a CA-signed certificate along with the response. If your site doesn&#39;t have https configured, then it must be listening at port 80 (and obviously would not need any certs).

This is fine for some applications. However, what if you want to put another web app on the same VM (because you&#39;re cheap, like me)? With this setup, you&#39;re going to need something in between your web applications to decide which one to forward the request to. That &#34;something&#34; is a reverse proxy. The person deciding to come to your site still enters https://your-awesome-domain.com into the browser. Before, her signal would look like: \[her\] -&gt; \[your web app\]. Now, her request signal looks like \[her\] -&gt; \[reverse proxy\] -&gt; \[your web app\].

Common reasons for reverse proxies include making zero downtime deployments much easier to do, handling certificate management for https-enabled sites, cramming as many web apps on your server as the thing can handle, or selectively caching content--which I will cover in the next post.

### Create an Ansible Role

I will use [Ansible](https://www.ansible.com/) to provision the server for this example. You will need ansible, molecule, vagrant, and virtual box on your machine to follow along.

Navigate to the directory that you want this project to go into and type:

``` bash
$ molecule init role -r reverse-proxy-nginx -d vagrant
```

I&#39;m using vagrant as the VM provider here, and the ansible role I&#39;m creating is called &#34;reverse-proxy-nginx.&#34; Modify the **molecule/default/molecule.yml** file&#39;s **providers** section to the following:

``` yaml
platforms:
  - name: reverse-proxy
    box: ubuntu/xenial64
    memory: 1024
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;
    interfaces:
    - auto_config: true
      network_name: private_network
      ip: 192.168.56.202
      type: static

```

The first thing we will need is a Spring MVC application to work with. For simplicity, we&#39;re going to keep the app source code within this ansible role. In a real application, you should set up a CI/CD pipeline that the application would go through, but I&#39;m going to keep the focus on getting a working example. Create a **app/** directory, then go to the [spring initializer](https://start.spring.io/) and select the &#34;Web&#34; dependency option, then Maven as the build engine. Place the generated code inside the **app/** directory.

We can then add a **SimpleController.java** class to the **app/src/main/java/com/nickolasfisher/simplemvc/** directory that is, well, simple:

``` java
package com.nickolasfisher.simplemvc;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class SimpleController {

    @GetMapping(&#34;/**&#34;)
    public ResponseEntity&lt;String&gt; simpleResponder() {
        return new ResponseEntity&lt;&gt;(&#34;&lt;h1&gt;Welcome to my site!&lt;/h1&gt;&#34;, HttpStatus.ACCEPTED);
    }
}

```

On the server, we are going to need Java and Nginx. In the [source code for this post](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx), I&#39;ve included two separate roles called **openjdk** and **nginx**. The ansible role that gets Java looks like:

``` yaml
---
- name: Get Java tarball
  get_url:
    url: &#34;{{ jdk_url }}&#34;
    dest: /etc/{{ jdk_tarball }}
  become: yes

- name: make java directory
  file:
    path: &#34;/usr/lib/openjdk-{{ jdk_version }}&#34;
    state: directory
  become: yes

- name: unpack tarball
  unarchive:
    dest: &#34;/usr/lib/openjdk-{{ jdk_version }}/&#34;
    src: /etc/{{ jdk_tarball }}
    remote_src: yes
  become: yes

- name: update alternatives for java
  alternatives:
    name: java
    path: &#34;/usr/lib/openjdk-{{ jdk_version }}/jdk-{{ jdk_version }}/bin/java&#34;
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

``` yaml
---
