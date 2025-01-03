---
title: "A Simple Zero Downtime Continuous Integration Pipeline for Spring MVC"
date: 2018-11-01T00:00:00
draft: false
---

The sample code associated with what follows can be found [on GitHub](https://github.com/nfisher23/simple-cicd-pipeline-with-spring).

One of the biggest paradigm shifts in software engineering, since the invention of the computer and software that would run on it, was the idea of a MVR (minimum viable release) or MVP (minimum viable product). With the lack of internet access becoming the exception in developed countries, it becomes more and more powerful to put your product out there on display, and to design a way to continuously make improvements to it. In the most aggressive of circumstances, you want to be able to push something up to a source control server, then let an automated process perform the various steps required to actually deploy it in the real world. In the best case, you can achieve all of this with zero downtime--basically, the users of your service are never inconvenienced by your decision to make a change. Setting up one very simple example of that is the subject of this post.

I&#39;ll start with a skeleton Spring MVC project. You can use the [Spring Initializer](https://start.spring.io/) with the Web option to get started quickly and easily. All I&#39;ll do, to keep the focus on DevOps, is add a simple entry controller that will accept requests to the root directory:

``` java
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

``` bash
#!/bin/bash

