---
title: "How to Forward Request Headers to Downstream Services in Spring Boot Webflux"
date: 2020-07-01T00:00:00
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/context-api).

When you make the switch to a reactive codebase, [ThreadLocal](https://docs.oracle.com/javase/7/docs/api/java/lang/ThreadLocal.html) becomes effectively off limits to you, because you aren&#39;t guaranteed that the thread that starts the request processing remains the same, even if it&#39;s the same HTTP request. This has caused pain in many places: the original implementation of spring security, for example, relied very heavily on ThreadLocal variables to store state that happened in the start of the request, and then reuse the information stored in those variables later on to make access control decisions. [Neflix spoke of their pain migrating to a reactive stack](https://netflixtechblog.com/zuul-2-the-netflix-journey-to-asynchronous-non-blocking-systems-45947377fb5c), when they had relied so heavily on ThreadLocal variables in most of their shared libraries.

If you need to store state through the lifecycle of a request in a reactive stack, we have to go a little bit of a different way. Thankfully, in the case of project reactor, they have come up with a nifty abstraction that is very similar to ThreadLocal: [Context](https://projectreactor.io/docs/core/release/reference/#context). I elected to use Context to automatically forward a known request header downstream, which is very commonly needed in a microservices architecture, for example passing around an authentication token or tracking a user span.

## Simple Echo Server

To make things a little easier for me, I borrowed [a really simple python server that just prints out the request and the response](https://gist.github.com/huyng/814831). Note that I had to modify it slightly in order to get webflux to play nice with it and I also changed the port, the full code is here:

``` python
#!/usr/bin/env python
