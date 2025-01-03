---
title: "How to Map Multiple Headers to the Same Variable in Nginx"
date: 2020-05-24T20:26:02
draft: false
tags: [ngnix, DevOps]
---

The [nginx map module](http://nginx.org/en/docs/http/ngx_http_map_module.html) is a nifty tool that allows you to programmatically change behavior based on things like http headers that come in.

In this post, I'll show how to choose a different file to serve based on a custom header that comes in, then how to check multiple headers to make a final decision on where to go.

### Setting up the Playground

I'm going to use [docker compose](https://docs.docker.com/compose/) to walk us through this. If you make a **docker-compose.yml** file and set it up like so:

```yaml
version: "3.3"
services:
  nginx:
    image: nginx:latest
    ports:
      - 9000:80
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
      - ./nginx/primary.html:/usr/share/nginx/html/primary.html
      - ./nginx/secondary.html:/usr/share/nginx/html/secondary.html

```

We'll then create an **nginx** directory and throw four files in it: **nginx.conf**, **default.conf**, **primary.html**, and **secondary.html**.

**nginx.conf:**

```
user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {

    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    include /etc/nginx/conf.d/*.conf;
}

```

**default.conf**:

```
server {
    listen       80;
    server_name  localhost;

    #charset koi8-r;
    #access_log  /var/log/nginx/host.access.log  main;
    root /usr/share/nginx/html;

    location / {
        try_files '' /primary.html =404;
    }

    #error_page  404              /404.html;

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}

```

**primary.html**

```
<h1>The primary html page</h1>
```

**secondary.html**

```
<h1>The secondary, as in NOT primary, html page</h1>
```

### Working with maps

Right now, if you run:

```
docker-compose up
```

You can hit any endpoint on **localhost:9000** and get back the primary.html file. E.g.

```
$ curl localhost:9000/one
<h1>The primary html page</h1>
$ curl localhost:9000/two
<h1>The primary html page</h1>

```

What if we want to serve up the secondary html page based only on a certain custom header coming in? Well, then we can use variables. If we modify:

```
    location / {
        try_files '' /$actual_variable =404;
    }

```

Then we can use a map variable to serve up whatever file we want. Place this block of code outside the server block and restart the docker container:

```
map $http_x_new_header $actual_variable {
  ~secondary "secondary.html";
  default "primary.html";
}

```

Then you can still hit any endpoint like normal and get the primary.html page, but you can also specify a our x-new-header with the value of "secondary" and get the secondary.html page:

```
$ curl localhost:9000/something
<h1>The primary html page</h1>
$ curl -H "X-New-Header: secondary" localhost:9000/something
<h1>The secondary, as in NOT primary, html page</h1>
```

Pretty interesting. But one follow up question: what if we want two different headers to determine the outcome of this variable. For example, what if we have some legacy clients calling us with a legacy header, and we want to check the value of the legacy header as well as the new header? Well, we can nest maps:

```
map $http_x_legacy_header $default_variable {
  ~secondary "secondary.html";
  default "primary.html";
}

map $http_x_new_header $actual_variable {
  ~secondary "secondary.html";
  default $default_variable;
}
```

If you restart nginx now ( **docker-compose down &amp;&amp; docker-compose up -d**), you can see it in action:

```
# regular call
$ curl localhost:9000/endpoint
<h1>The primary html page</h1>

# using the new header like before
$ curl -H "X-New-Header: secondary" localhost:9000/something
<h1>The secondary, as in NOT primary, html page</h1>

# using the legacy header
$ curl -H "X-Legacy-Header: secondary" localhost:9000/something
<h1>The secondary, as in NOT primary, html page</h1>

# using both headers cause why not
$ curl -H "X-Legacy-Header: secondary" -H "X-New-Header: secondary" localhost:9000/something~
<h1>The secondary, as in NOT primary, html page</h1>

# notice what happens when the value is changed
$ curl -H "X-Legacy-Header: idk" -H "X-New-Header: huh" localhost:9000/something~
<h1>The primary html page</h1>

```
