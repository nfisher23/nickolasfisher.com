---
title: "How To Invalidate an Nginx Cache In a Reverse Proxy Setup With Spring MVC"
date: 2019-04-13T16:52:53
draft: false
---

You can see the sample code associated with this post [on Github](https://github.com/nfisher23/some-ansible-examples/tree/master/reverse-proxy-nginx).

In two previous posts, we looked at how to [provision a reverse proxy using nginx](https://nickolasfisher.com/blog/How-to-Deploy-a-Spring-MVC-Application-Behind-an-Nginx-Reverse-Proxy) and then [how to add caching to the nginx reverse proxy](https://nickolasfisher.com/blog/How-to-Use-Nginxs-Caching-to-Improve-Site-Responsiveness). The implementation we ended up with at the end of the last post was a &#34;dumb&#34; cache, meaning that it doesn&#39;t know when or if any data gets updated--it just times out after 60 seconds and then asks for a new payload from the application it&#39;s acting as proxy for.

In this post, I&#39;ll demonstrate a simple way to invalidate the cache under predefined conditions using Spring Boot. This will allow us to programmatically and selectively notify Nginx to request a new payload. This way, users will get a fast page-load time combined with up-to-date information, depending on the use case.

The first thing we will do is create a simple one-line bash script that &#34;invalidates&#34; the cache. For Nginx, that can simply mean removing the cache contents. In our Nginx ansible role, I&#39;m adding a Jinja2 template in **templates/invalidate\_cache.sh.j2**:

```bash
#!/bin/bash
rm -rf {{ nginx_cache_path }}/*
```

This uses our ansible variable to recursively remove all of the contents of the nginx cache. We will also add this script to our path so any application can easily use it. Add this to our **nginx** role:

```yaml
- name: add invalidate cache script to path
  template:
    src: invalidate_cache.sh.j2
    dest: &#34;/usr/bin/{{ nginx_cache_invalidate_script_name }}&#34;
    mode: 0755
  become: yes
  notify: restart nginx
```

This also uses a variable, which we will have to add to **vars/main.yml** in our nginx role:

```yaml
nginx_cache_invalidate_script_name: invalidate_nginx_cache
```

Now this is available for our sample application to use. In the code itself, I have elected to leverage [Spring&#39;s Aspect Oriented Programming](https://docs.spring.io/spring/docs/2.5.x/reference/aop.html) to abstract over the cache invalidation process. We will first have to add the AOP dependency to our **pom.xml**:

```xml
&lt;dependency&gt;
    &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
    &lt;artifactId&gt;spring-boot-starter-aop&lt;/artifactId&gt;
    &lt;version&gt;2.1.3.RELEASE&lt;/version&gt;
&lt;/dependency&gt;

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

    @After(&#34;execution(* *(..)) &amp;&amp; @annotation(InvalidateNginxCache)&#34;)
    private void invalidateTheCache() {
        ProcessBuilder pb = new ProcessBuilder(&#34;invalidate_nginx_cache&#34;);
        try {
            pb.start();
        } catch (Exception ignored) {
            // feel free to handle this differently
            throw new RuntimeException(&#34;Houston, this didn&#39;t&#34;);
        }
    }
}

```

We can then use this anywhere a method gets executed--after the method completes, this code will run and invalidate the cache. I&#39;ve elected to demonstrate this in our **SimpleController.java** class:

```java
package com.nickolasfisher.simplemvc;

... imports ...

@Controller
public class SimpleController {

    private static String hotValue = &#34;starter&#34;;

    @GetMapping(&#34;/slow&#34;)
    public ResponseEntity&lt;String&gt; slowEndpoint() throws InterruptedException {
        Thread.sleep(2500);
        return new ResponseEntity&lt;&gt;(&#34;&lt;p&gt;Takes a while to get: &#34; &#43; hotValue &#43; &#34; &lt;/p&gt;&#34;, HttpStatus.ACCEPTED);
    }

    @PostMapping(&#34;/api/hotValue&#34;)
    @InvalidateNginxCache
    public RedirectView updateHotValue(@RequestBody JsonNode body) {
        hotValue = body.get(&#34;hotValue&#34;).textValue();
        return new RedirectView(&#34;/slow&#34;);
    }

    @GetMapping(&#34;/&#34;)
    public ResponseEntity&lt;String&gt; simpleResponder() {
        return new ResponseEntity&lt;&gt;(&#34;&lt;h1&gt;Welcome to my site!&lt;/h1&gt;&#34;, HttpStatus.ACCEPTED);
    }
}

```

Getting the source code and running:

```bash
$ molecule create &amp;&amp; molecule converge
```

Will then allow you to hit the [http://192.168.56.202/slow](http://192.168.56.202/slow) endpoint. It will cache after the first request like before. If you then hit the api endpoint:

```bash
$ curl -XPOST http://192.168.56.202/api/hotValue -H &#34;Content-Type: application/json&#34; --data &#39;{&#34;hotValue&#34;:&#34;some new value&#34;}&#39;

```

Then, regardless of how long the cache would have remained active, you will see the new value updated.

**Note**: This did not work on Ubuntu 16. I had to upgrade the VM to Ubuntu 18. I did not investigate why, but it had something to do with the way nginx was trying to create new directories once they were invalidated.
