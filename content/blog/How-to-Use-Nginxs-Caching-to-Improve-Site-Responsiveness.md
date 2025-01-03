---
title: "How to Use Nginx&#39;s Caching to Improve Site Responsiveness"
date: 2019-04-01T00:00:00
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx).

In my last post, I provided an example for [how to set up an Nginx Reverse Proxy for a Spring MVC application](https://nickolasfisher.com/blog/How-to-Deploy-a-Spring-MVC-Application-Behind-an-Nginx-Reverse-Proxy). One such reason to set up a reverse proxy is to utilize caching of resources. If you have dynamically generated content that doesn&#39;t change very often, then adding caching at the site entry point can dramatically improve site responsiveness and reduce load on critical resources.

You will want to be sure to have a good background in setting up a reverse proxy with nginx to get the most out of this post, and I will be building on the work that was done in the last post.

### Simulating a Long Running Process

First, we&#39;ll add an endpoint in our Spring MVC application that simulates taking a long time to get a result. Maybe the database is overwhelmed, or maybe a GC process stops the world more often than we would like:

``` java
package com.nickolasfisher.simplemvc;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class SimpleController {

    @GetMapping(&#34;/slow&#34;)
    public ResponseEntity&lt;String&gt; slowEndpoint() throws InterruptedException {
        Thread.sleep(2500);
        return new ResponseEntity&lt;&gt;(&#34;&lt;p&gt;Well... that took awhile&lt;/p&gt;&#34;, HttpStatus.ACCEPTED);
    }

    @GetMapping(&#34;/&#34;)
    public ResponseEntity&lt;String&gt; simpleResponder() {
        return new ResponseEntity&lt;&gt;(&#34;&lt;h1&gt;Welcome to my site!&lt;/h1&gt;&#34;, HttpStatus.ACCEPTED);
    }
}

```

Here, when we hit the /slow endpoint, it will take 2.5 seconds to get a response--an eternity on the internet. That represents ~25% loss in revenue for Amazon, should its site load that slowly.

If you run:

``` bash
$ molecule create &amp;&amp; molecule converge
```

And request [http://192.168.56.202/slow,](http://192.168.56.202/slow,) you will see it in action. Moreover, it will take 2.5 seconds _every time_, despite the fact that the content is not changing. This is a perfect candidate for a caching layer.

### Set up the Cache in Nginx

Setting up a cache is relatively straightforward. We can specify a cache with [proxy\_cache\_path](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_path). Some common parameters are max\_size, levels, and the use\_temp\_path flag. **use\_temp\_path** should be set to **off**, or else there will be an unnecessary intermediate step where nginx copies files.

I&#39;ll declare a proxy\_cache\_path above the server block in our **server.conf.j2** Jinja2 template for our **nginx role**, which is called as a dependency in the reverse-proxy-nginx role. I will add some parameters, including a way to easily turn off the cache with a **nginx\_use\_cache** flag:

```
{% if nginx_use_cache %}
proxy_cache_path {{ nginx_cache_path }} levels=1:2 keys_zone={{ nginx_cache_name }}:10m max_size=10g
                 inactive=60m use_temp_path=off;
{% endif %}

server {
    ...server block...
}
```

Add the variables to the **nginx/vars/main.yml** file so it looks like:

``` yaml
---
