---
title: "How to Use Nginx's Caching to Improve Site Responsiveness"
date: 2019-04-06T17:14:30
draft: false
tags: [java, ngnix, vagrant, ansible, spring, DevOps, maven]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx).

In my last post, I provided an example for [how to set up an Nginx Reverse Proxy for a Spring MVC application](https://nickolasfisher.com/blog/how-to-deploy-a-spring-mvc-application-behind-an-nginx-reverse-proxy). One such reason to set up a reverse proxy is to utilize caching of resources. If you have dynamically generated content that doesn't change very often, then adding caching at the site entry point can dramatically improve site responsiveness and reduce load on critical resources.

You will want to be sure to have a good background in setting up a reverse proxy with nginx to get the most out of this post, and I will be building on the work that was done in the last post.

### Simulating a Long Running Process

First, we'll add an endpoint in our Spring MVC application that simulates taking a long time to get a result. Maybe the database is overwhelmed, or maybe a GC process stops the world more often than we would like:

```java
package com.nickolasfisher.simplemvc;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class SimpleController {

    @GetMapping("/slow")
    public ResponseEntity<String> slowEndpoint() throws InterruptedException {
        Thread.sleep(2500);
        return new ResponseEntity<>("<p>Well... that took awhile</p>", HttpStatus.ACCEPTED);
    }

    @GetMapping("/")
    public ResponseEntity<String> simpleResponder() {
        return new ResponseEntity<>("<h1>Welcome to my site!</h1>", HttpStatus.ACCEPTED);
    }
}

```

Here, when we hit the /slow endpoint, it will take 2.5 seconds to get a response--an eternity on the internet. That represents ~25% loss in revenue for Amazon, should its site load that slowly.

If you run:

```bash
$ molecule create &amp;&amp; molecule converge
```

And request [http://192.168.56.202/slow,](http://192.168.56.202/slow,) you will see it in action. Moreover, it will take 2.5 seconds _every time_, despite the fact that the content is not changing. This is a perfect candidate for a caching layer.

### Set up the Cache in Nginx

Setting up a cache is relatively straightforward. We can specify a cache with [proxy\_cache\_path](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_path). Some common parameters are max\_size, levels, and the use\_temp\_path flag. **use\_temp\_path** should be set to **off**, or else there will be an unnecessary intermediate step where nginx copies files.

I'll declare a proxy\_cache\_path above the server block in our **server.conf.j2** Jinja2 template for our **nginx role**, which is called as a dependency in the reverse-proxy-nginx role. I will add some parameters, including a way to easily turn off the cache with a **nginx\_use\_cache** flag:

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

```yaml
---
# vars file for nginx
app_port: 8080
site_alias: my-site
remove_nginx_defaults: true

nginx_cache_path: /etc/nginx/cache
nginx_cache_name: my_cache
nginx_use_cache: true
```

If you deploy this now, the parsed nginx conf file will result in a proxy\_cache\_path declaration looking like:

```
proxy_cache_path /etc/nginx/cache levels=1:2 keys_zone=my_cache:10m max_size=10g
                 inactive=60m use_temp_path=off;
```

However, nothing will change yet--the slow endpoint will still take 2.5 seconds, because we aren't using the cache yet. To start using it, we have to declare the cache in the location block, then specify how long we want it to be valid for. In our case, we will also have to ensure that the proxy\_cache\_bypass declaration is not in place. Because Nginx, by default, honors the Cache-Control header (which is usually used to specify that the client wants the newest version of this resource) and _we know the content has not changed,_ we will also tell Nginx to ignore the Cache-Control header. Our **server.conf.j2** file in the nginx role can finally look like:

```
{% if nginx_use_cache %}
proxy_cache_path {{ nginx_cache_path }} levels=1:2 keys_zone={{ nginx_cache_name }}:10m max_size=10g
                 inactive=60m use_temp_path=off;
{% endif %}

server {
    location / {
{% if nginx_use_cache %}
        proxy_cache {{ nginx_cache_name }};
        proxy_ignore_headers Cache-Control;
        proxy_cache_valid any 60s;

{% endif %}
        proxy_pass http://localhost:{{ app_port }};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $http_host;
{% if not nginx_use_cache %}
        proxy_cache_bypass $http_upgrade;
{% endif %}
    }
}

```

When you run:

```bash
$ molecule converge
```

You should now see the parsed Jinja file looking like:

```
proxy_cache_path /etc/nginx/cache levels=1:2 keys_zone=my_cache:10m max_size=10g
                 inactive=60m use_temp_path=off;

server {
    location / {
        proxy_cache my_cache;
        proxy_cache_valid any 60s;

        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $http_host;
    }
}

```

And, most importantly, the [http:/192.168.56.202/slow](http:/192.168.56.202/slow) endpoint gets cached. The first time will take 2.5 seconds, but every subsequent request takes about 1ms (on my machine). The cache, in the way we have configured it, is valid for 60 seconds, then will invalidate itself.

Some further reading:

- [NGINX Content Caching](https://docs.nginx.com/nginx/admin-guide/content-cache/content-caching/)
- [A Guide to Caching with NGINX and NGINX Plus](https://www.nginx.com/blog/nginx-caching-guide/)
