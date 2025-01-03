---
title: "The Hystrix Parameters You Actually Need to Tune in Spring Boot"
date: 2020-06-13T17:53:33
draft: false
tags: [java, spring]
---

There is some \[hacky\] code for this post [on Github](https://github.com/nfisher23/hystrix-playground).

The [number of hystrix configuration options](https://github.com/Netflix/Hystrix/wiki/Configuration), as of this writing, is about 34. In reality, you don't need to worry about most of them, as the defaults are perfectly reasonable. This article discusses those parameters that, in my experience, you typically need to pay attention to and tune, and I have provided some examples using spring boot's support for hystrix via the [javanica library](https://github.com/Netflix/Hystrix/tree/master/hystrix-contrib/hystrix-javanica).

## Fallback

By default, there is no fallback, which means when the operation fails the exception just bubbles up to the client. For the vast majority of GET requests, it is better to give the user stale data (that you've presumably cached upstream as a backup) than no data at all, or give the user an error modal on whatever client facing app is consuming it.

To setup a fallback, use the **fallbackMethod** property like so:

```java
    @HystrixCommand(
            fallbackMethod = "fallback")
    public String getDownstream(String uuid) {
        LOG.info("inside getDownstream with: {}", uuid);
        return this.longRestTemplate.getForEntity("http://localhost:9100/downstream", String.class).getBody();
    }

    private String fallback(String uuid, Throwable t) {
        LOG.warn("ex: {}", t.getClass());
        LOG.warn("Thrown: {}", t.getMessage());
        return "fallback";
    }

```

This will execute the fallback method and just log the exception that caused it--whether it was an intermittent error or the circuit tripped and all requests are now being blocked.

## Thread Pool Key

By default, hystrix will use the same threadpool for all configured **HystrixCommand** s. This is very rarely what you want, because it means that operations that are likely unrelated can both saturate the shared thread pool (causing **RejectedExecutionException** s if too many get backed up, the point of the bulkhead), as well can trip the circuit for everybody else.

If you set the thread pool key, then the library will create a separate threadpool that is not the default and give you the isolation between components that is a key reason to want to use hystrix in the first place: to give users a degraded experience that recovers more quickly, rather than giving users no experience at all because your app is borked:

```java
    @HystrixCommand(
            threadPoolKey = "prim",
            fallbackMethod = "fallback")
    public String getDownstream(String uuid) {
        LOG.info("inside getDownstream with: {}", uuid);
        return this.longRestTemplate.getForEntity("http://localhost:9100/downstream", String.class).getBody();
    }

    private String fallback(String uuid, Throwable t) {
        LOG.warn("ex: {}", t.getClass());
        LOG.warn("Thrown: {}", t.getMessage());
        return "fallback";
    }
```

Here, hystrix will create a thread pool and label the prefix with **prim**. Trip this circuit and the main thread pool will be unaffected and continue to process requests independently.

## Thread Execution Timeout

Almost always, hystrix is used to protect against failures from network calls. If we could guarantee that there were no bugs in the library we were using to execute those network calls, then the **execution.isolation.thread.timeoutInMilliseconds** property would be useless or even harmful. However, there are bugs everywhere, this is the nature of human beings writing software.

Hystrix by default will delegate the actual execution of the code in a **HystrixCommand** to a different spawned thread, and watch it. If it takes too long (default is 1 second or 1000 milliseconds), then hystrix will nuke that thread midway through whatever it's doing. If, for example, you are making a network call and have a three second timeout, then you're nuking a thread that was still active and that was just waiting for the downstream operation to occur.

You should set this property to a millisecond value that should theoretically never occur. If you've set up the read timeout for a REST API call to be 3000 milliseconds, then you should set this to something like 4000 milliseconds--only necessary if there is a bug somewhere in the library that you're using. You can set it like so:

```java
    @HystrixCommand(commandProperties = {
            @HystrixProperty(name = "execution.isolation.thread.timeoutInMilliseconds", value = "2000")
    },
            threadPoolKey = "prim",
            fallbackMethod = "fallback")
    public String getDownstream(String uuid) {
        LOG.info("inside getDownstream with: {}", uuid);
        return this.longRestTemplate.getForEntity("http://localhost:9100/downstream", String.class).getBody();
    }

    private String fallback(String uuid, Throwable t) {
        LOG.warn("ex: {}", t.getClass());
        LOG.warn("Thrown: {}", t.getMessage());
        return "fallback";
    }

```

Here, we set it to 2000 milliseconds.

## Core Pool Size

The "thread pool" in a hystrix thread pool isn't really a thread pool so much as a gate to prevent over usage. Yes, a different thread is technically delegated to, but rather than be a buffer to balance the workload it is primarily meant to be a way to stop too much of the application's resources being saturated in a single misbehaving block of code. By default, the **coreSize** of the thread pool is 10 with no backing queue to wait for requests, which means that at any given time, only ten requests can be executing. This is usually fine, but can sometimes be a bit restrictive and you might want this to be higher. You can set it like so:

```java
    @HystrixCommand(commandProperties = {
            @HystrixProperty(name = "execution.isolation.thread.timeoutInMilliseconds", value = "2000")
    },
            threadPoolKey = "prim",
            threadPoolProperties = {
                    @HystrixProperty(name = "coreSize", value = "30")
            },
            fallbackMethod = "fallback")
    public String getDownstream(String uuid) {
        LOG.info("inside getDownstream with: {}", uuid);
        return this.longRestTemplate.getForEntity("http://localhost:9100/downstream", String.class).getBody();
    }

    private String fallback(String uuid, Throwable t) {
        LOG.warn("ex: {}", t.getClass());
        LOG.warn("Thrown: {}", t.getMessage());
        return "fallback";
    }

```

Here, the core pool size is set to thirty.

## Circuit Breaker Sleep Window

This property isn't really that important unless you're operating at significant scale, but I thought I would mention it because it can sometimes matter. The **hystrix.command.default.circuitBreaker.sleepWindowInMilliseconds** property defines how long to wait after a circuit trips before letting a request through to poke the downstream dependency. By default, it's five seconds, which in my experience is too conservative because it only lets one request through every five seconds until a successful response. I prefer for this to be 1-3 seconds, depending on the quirks of the system you're working with. There are also cases where making this number larger works, it again depends on the quirks of your system.

You set this in the **commandProperties** section with the **name** of **circuitBreaker.sleepWindowInMilliseconds** and a value in milliseconds, e.g. 1000. We'll leave that exercise to the reader :)

I threw up some kind of crummy code in this github repository: [https://github.com/nfisher23/hystrix-playground.](https://github.com/nfisher23/hystrix-playground.) Feel free to clone it and modify it as you see fit.
