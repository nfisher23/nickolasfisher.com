---
title: "How To Invalidate an Nginx Cache In a Reverse Proxy Setup With Spring MVC"
date: 2019-04-13T16:52:53
draft: false
tags: [java, ngnix, aspect oriented programming, ansible, spring, DevOps]
---

You can see the sample code associated with this post [on Github](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx).

In two previous posts, we looked at how to [provision a reverse proxy using nginx](https://nickolasfisher.com/blog/how-to-deploy-a-spring-mvc-application-behind-an-nginx-reverse-proxy) and then [how to add caching to the nginx reverse proxy](https://nickolasfisher.com/blog/how-to-use-nginxs-caching-to-improve-site-responsiveness). The implementation we ended up with at the end of the last post was a "dumb" cache, meaning that it doesn't know when or if any data gets updated--it just times out after 60 seconds and then asks for a new payload from the application it's acting as proxy for.

In this post, I'll demonstrate a simple way to invalidate the cache under predefined conditions using Spring Boot. This will allow us to programmatically and selectively notify Nginx to request a new payload. This way, users will get a fast page-load time combined with up-to-date information, depending on the use case.

The first thing we will do is create a simple one-line bash script that "invalidates" the cache. For Nginx, that can simply mean removing the cache contents. In our Nginx ansible role, I'm adding a Jinja2 template in **templates/invalidate\_cache.sh.j2**:

```bash
#!/bin/bash
rm -rf {{ nginx_cache_path }}/*
```

This uses our ansible variable to recursively remove all of the contents of the nginx cache. We will also add this script to our path so any application can easily use it. Add this to our **nginx** role:

```yaml
- name: add invalidate cache script to path
  template:
    src: invalidate_cache.sh.j2
    dest: "/usr/bin/{{ nginx_cache_invalidate_script_name }}"
    mode: 0755
  become: yes
  notify: restart nginx
```

This also uses a variable, which we will have to add to **vars/main.yml** in our nginx role:

```yaml
nginx_cache_invalidate_script_name: invalidate_nginx_cache
```

Now this is available for our sample application to use. In the code itself, I have elected to leverage [Spring's Aspect Oriented Programming](https://docs.spring.io/spring/docs/2.5.x/reference/aop.html) to abstract over the cache invalidation process. We will first have to add the AOP dependency to our **pom.xml**:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aop</artifactId>
    <version>2.1.3.RELEASE</version>
</dependency>

```

Then, we will create an interface to decorate any method that we want to invalidate the cache **(InvalidateNginxCache.java)**:

```java
package com.nickolasfisher.simplemvc;

public @interface InvalidateNginxCache { }

```

To actually invalidate the cache, we will define our pointcut and use ProcessBuilder to execute our invalidate\_nginx\_cache script, which is assumed to be on the system path:

```java
package com.nickolasfisher.simplemvc;

import org.aspectj.lang.annotation.After;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.stereotype.Component;

import java.util.Map;

@Aspect
@Component
public class AutoCacheInvalidator {

    @After("execution(* *(..)) &amp;&amp; @annotation(InvalidateNginxCache)")
    private void invalidateTheCache() {
        ProcessBuilder pb = new ProcessBuilder("invalidate_nginx_cache");
        try {
            pb.start();
        } catch (Exception ignored) {
            // feel free to handle this differently
            throw new RuntimeException("Houston, this didn't");
        }
    }
}

```

We can then use this anywhere a method gets executed--after the method completes, this code will run and invalidate the cache. I've elected to demonstrate this in our **SimpleController.java** class:

```java
package com.nickolasfisher.simplemvc;

... imports ...

@Controller
public class SimpleController {

    private static String hotValue = "starter";

    @GetMapping("/slow")
    public ResponseEntity<String> slowEndpoint() throws InterruptedException {
        Thread.sleep(2500);
        return new ResponseEntity<>("<p>Takes a while to get: " + hotValue + " </p>", HttpStatus.ACCEPTED);
    }

    @PostMapping("/api/hotValue")
    @InvalidateNginxCache
    public RedirectView updateHotValue(@RequestBody JsonNode body) {
        hotValue = body.get("hotValue").textValue();
        return new RedirectView("/slow");
    }

    @GetMapping("/")
    public ResponseEntity<String> simpleResponder() {
        return new ResponseEntity<>("<h1>Welcome to my site!</h1>", HttpStatus.ACCEPTED);
    }
}

```

Getting the source code and running:

```bash
$ molecule create &amp;&amp; molecule converge
```

Will then allow you to hit the [http://192.168.56.202/slow](http://192.168.56.202/slow) endpoint. It will cache after the first request like before. If you then hit the api endpoint:

```bash
$ curl -XPOST http://192.168.56.202/api/hotValue -H "Content-Type: application/json" --data '{"hotValue":"some new value"}'

```

Then, regardless of how long the cache would have remained active, you will see the new value updated.

**Note**: This did not work on Ubuntu 16. I had to upgrade the VM to Ubuntu 18. I did not investigate why, but it had something to do with the way nginx was trying to create new directories once they were invalidated.
