---
title: "A Simple Zero Downtime Continuous Integration Pipeline for Spring MVC"
date: 2018-11-25T15:53:22
draft: false
---

The sample code associated with what follows can be found [on GitHub](https://github.com/nfisher23/simple-cicd-pipeline-with-spring).

One of the biggest paradigm shifts in software engineering, since the invention of the computer and software that would run on it, was the idea of a MVR (minimum viable release) or MVP (minimum viable product). With the lack of internet access becoming the exception in developed countries, it becomes more and more powerful to put your product out there on display, and to design a way to continuously make improvements to it. In the most aggressive of circumstances, you want to be able to push something up to a source control server, then let an automated process perform the various steps required to actually deploy it in the real world. In the best case, you can achieve all of this with zero downtime--basically, the users of your service are never inconvenienced by your decision to make a change. Setting up one very simple example of that is the subject of this post.

I&#39;ll start with a skeleton Spring MVC project. You can use the [Spring Initializer](https://start.spring.io/) with the Web option to get started quickly and easily. All I&#39;ll do, to keep the focus on DevOps, is add a simple entry controller that will accept requests to the root directory:

```java
@Controller
public class HelloWorldController {

    @GetMapping(value = {&#34;/&#34;, &#34;&#34;})
    public ResponseEntity&lt;String&gt; notAnotherHelloWorld() {
        return new ResponseEntity&lt;&gt;(&#34;okay, I guess we&#39;ll call this a hello world&#34;, HttpStatus.OK);
    }
}
```

As you can see, I&#39;m reluctantly calling this a &#34;hello world.&#34; Yuck.

And that&#39;s it for the Spring MVC project. What we need on the server is:

1. Dependencies (e.g. java)
2. A source control server (to checkout the code and perform the steps on commit)
3. A way to build the solution in a way that is separate from running our solution
4. A way for the web application to run continuously, and to restart automatically if it crashes

5. A reverse proxy server to balance requests between two active
   applications. When one is stopped for upgrades, the second can continue
   to run, and vice versa.

I will start with #4: we can [create a systemctl service](https://www.digitalocean.com/community/tutorials/how-to-use-systemctl-to-manage-systemd-services-and-units) (call this **site-node1.service**):

```
[Unit]
Description=Site Node 1

[Service]
ExecStart=/usr/bin/java -jar -Xmx64m /opt/site-node1/target/simplecicd-0.0.1-SNAPSHOT.jar
Restart=always
RestartSec=10
SyslogIdentifier=site-node1
Environment=SERVER_PORT=9000

[Install]
WantedBy=multi-user.target

```

This runs with the environment variable SERVER\_PORT equal to 9000, which tells Spring to run our application on [localhost:9000](localhost:9000) (which will be the local host on the server). We can create another service file for another port (9001, here) like so (call this **site-node2.service**):

```
[Unit]
Description=Site Node 2

[Service]
ExecStart=/usr/bin/java -jar -Xmx64m /opt/site-node2/target/simplecicd-0.0.1-SNAPSHOT.jar
Restart=always
RestartSec=10
SyslogIdentifier=site-node2
Environment=SERVER_PORT=9001

[Install]
WantedBy=multi-user.target

```

By choosing to use the local host to bind these systemctl service files to, we are capable of using a [reverse proxy](https://www.nginx.com/resources/glossary/reverse-proxy-server/). Typically, a lightweight server application gets the job done from here. I will choose [Nginx](https://www.nginx.com/), and create a dead simple configuration file like so:

```
upstream nodes {
        server localhost:9000;
        server localhost:9001;
}

server {
        # balance between nodes
        location / {
                proxy_pass http://nodes;
        }
}

```

Here, we use the load balancing feature to go between the two nodes defined in our service files above. Nginx will automatically detect if a port is not in use, and will not forward to that port if there is nothing to forward it to. For example, if both nodes are running and we decide to kill the one running on [localhost:9000,](localhost:9000,) Nginx will route all requests to [localhost:9001.](localhost:9001.)

I will use Git for source control, and will use [git&#39;s hooks feature](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks), particularly the post-receive file, to run a bash script on check in. The bash script will build the solution (including running any tests) and, if successful, will copy the directory with the built solution into our predetermined folder, then restart each service. Before starting the second service it will validate that the first one came up successfully, thus never shutting down both services at the same time:

```bash
#!/bin/bash

# checkout changes to release branch
git --work-tree=/opt/build --git-dir=/srv/git/site.git checkout -f release

# build the solution with maven and ensure it passes all the tests. If it fails, abort
cd /opt/build
mvn clean install
if [[ &#34;$?&#34; -ne 0 ]]; then
  echo &#34;build failed, stopping deployment&#34;
  exit 1
fi

rm -r /opt/site-node1/*
cp -r /opt/build/target /opt/site-node1/
echo &#34;restarting the first service&#34;
systemctl start site-node1.service
systemctl enable site-node1.service

START_TIME=&#34;$(date &#43;%s)&#34;

while [[ `curl -s -o /dev/null -w &#34;%{http_code}&#34; localhost:9000` -ne 200 ]]; do
  sleep 2s
  if [[ `expr $(date &#43;%s) - $START_TIME` -ge 60 ]]; then
    echo &#34;timed out--something is wrong. Aborting...&#34;
    exit 1
  fi
done

echo &#34;first service up, restarting second service&#34;
# stop the second service
systemctl stop site-node2.service
# copy the target directory from the build into the second node directory
rm -r /opt/site-node2/*
cp -r /opt/build/target /opt/site-node2/
# restart the second service
systemctl start site-node2.service
systemctl enable site-node2.service

```

To stitch all of this together, I will use an ansible playbook to provision our server, and I will use Vagrant as a proof of concept. Here&#39;s the playbook, which sets up the environment we need to make all of this work:

```yaml
---
- hosts: all
  become: yes
  gather_facts: no
  pre_tasks:
    - name: &#39;install python2 on ubuntu 18&#39;
      raw: test -e /usr/bin/python || (apt-get -y update &amp;&amp; apt-get install -y python-minimal)

  tasks:
    - name: Gathering facts
      setup:

    - name: Get Java tarball
      get_url:
        url: https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz
        dest: /etc/open-jdk10.tar.gz

    - name: make java 10 directory
      file:
        path: /usr/lib/java10
        state: directory

    - name: unpack tarball
      unarchive:
        dest: /usr/lib/java10/
        src: /etc/open-jdk10.tar.gz
        remote_src: yes

    - name: update alternatives for java
      alternatives:
        name: java
        path: /usr/lib/java10/jdk-10.0.1/bin/java
        link: /usr/bin/java
        priority: 2000

    - name: set java environment variable
      blockinfile:
        insertafter: EOF
        path: /etc/environment
        block: export JAVA_HOME=/usr/lib/java10/jdk-10.0.1

    - name: re-source env variables
      shell: . /etc/environment

    - name: install packages
      apt:
        name: &#39;{{ item }}&#39;
        state: present
        update_cache: yes
      with_items:
        - nginx
        - maven
        - git
        - python-psycopg2

    - name: allow ssh
      ufw:
        rule: allow
        name: OpenSSH

    - name: allow http/https
      ufw:
        rule: allow
        port: &#39;{{ item }}&#39;
      with_items:
        - 443
        - 80

    - name: setup rate limit over ssh
      ufw:
        rule: limit
        port: ssh
        proto: tcp

    - name:
      ufw:
        state: enabled

    - name: create git directory and node directories
      file:
        path: &#39;{{ item }}&#39;
        state: directory
        mode: 0777
      with_items:
        - /srv/git/site.git
        - /opt/site-node1
        - /opt/site-node2
        - /opt/build

    - name: create git repo to push to
      command: git init --bare /srv/git/site.git
      args:
        creates: /srv/git/site.git/HEAD

    - name: copy node service files
      copy:
        src: &#39;{{ item }}&#39;
        dest: /etc/systemd/system
        mode: 0755
      with_items:
        - ./site-node1.service
        - ./site-node2.service

    - name: copy nginx config file
      copy:
        src: ./nginx_site_conf
        dest: /etc/nginx/sites-available

    - name: make link to sites-enabled
      file:
        src: /etc/nginx/sites-available/nginx_site_conf
        dest: /etc/nginx/sites-enabled/nginx_site_conf
        state: link

    - name: remove default configuration
      file:
        path: /etc/nginx/sites-enabled/default
        state: absent
      register: nginxconf

    - name: reload nginx
      command: nginx -s reload
      when: nginxconf.changed

    - name: ensure nginx runs on boot
      service:
        name: nginx
        enabled: yes

    - name: create post-receive file to deploy solution on check in
      copy:
        src: ./post-receive.sh
        dest: /srv/git/site.git/hooks/post-receive
        mode: 0777

```

If you go [get the source code and install the prerequisites](https://github.com/nfisher23/simple-cicd-pipeline-with-spring), you can validate that this works by running:

```
$ vagrant up
```

Then, once the VM is provisioned:

```bash
$ git remote add local_vagrant root@192.168.56.121:/srv/git/site.git
```

Finally:

```bash
$ git push local_vagrant release
```

And watch the magic happen.
