---
title: "How to Configure Reactive Netty in Spring Boot, in Depth"
date: 2019-07-06T14:30:43
draft: false
tags: [java, spring, concurrency, reactive]
---

[Spring Boot's WebFlux programming model](https://docs.spring.io/spring/docs/current/spring-framework-reference/web-reactive.html) is pretty neat, but there isn't a lot by way of explaining how to best leverage it to get the results you need. I wrote this blog post after tinkering with the configuration of Reactor Netty on Spring Boot.

The first point, before we begin, to realize about the event loop model is that we want to reuse threads across all operations, and then insure that those operations utilize non-blocking behavior. This is contrary to the asynchronous and blocking behavior in the past (e.g. Servlets), where we often want to designate specific thread pools for specific actions and reduce the probability that one misbehaving process or operation brings down the entire application. That idea is called the [bulkhead pattern](https://docs.microsoft.com/en-us/azure/architecture/patterns/bulkhead), and it does not apply here. If that's confusing to you (which it is to most people at first), follow up with the blog post directly after this one for a more in depth example and discussion.

With that in mind, the first thing we're going to want to do is reuse an event loop group, which I'll demonstrate below.

### Create the Reactive WebFlux App

Go to the [spring initializr](https://start.spring.io/), select WebFlux, and unzip to your desired directory. By default, it comes with Reactor Netty.

From our discussion above, it makes sense to have one event loop group, which represents a group of threads that all consume work from a queue, pick it up, and try to release that work as quickly as possible in a non-blocking way. We can choose from most of the classes that implement Netty's [EventLoopGroup](https://netty.io/4.0/api/io/netty/channel/EventLoopGroup.html), or if we are feeling ambitious we could hand roll our own. I will choose [NioEventLoopGroup](https://netty.io/4.0/api/io/netty/channel/nio/NioEventLoopGroup.html) and create a bean, so that the entry point looks like this:

```java
@SpringBootApplication
public class ReactiveexApplication {

    public static void main(String[] args) throws InterruptedException {
        SpringApplication.run(ReactiveexApplication.class, args);
    }

    @Bean
    public NioEventLoopGroup nioEventLoopGroup() {
        return new NioEventLoopGroup(20);
    }
}

```

To customize the web server, we will have to provide a `NettyReactiveWebServerFactory` bean and use the event loop group we have already defined:

```java
    @Bean
    public NettyReactiveWebServerFactory factory(NioEventLoopGroup eventLoopGroup) {
        NettyReactiveWebServerFactory factory = new NettyReactiveWebServerFactory();
        factory.setServerCustomizers(Collections.singletonList(new NettyServerCustomizer() {
            @Override
            public HttpServer apply(HttpServer httpServer) {
                return httpServer.tcpConfiguration(tcpServer ->
                                tcpServer.bootstrap(serverBootstrap -> serverBootstrap.group(eventLoopGroup)
                                                        .channel(NioServerSocketChannel.class)));
            }
        }));
        return factory;
    }

```


To customize the `WebClient` we will have to register a `ReactorResourceFactory` that intentionally does not use the global resources, since we are defining our own:

```java
    @Bean
    public ReactorResourceFactory reactorResourceFactory(NioEventLoopGroup eventLoopGroup) {
        ReactorResourceFactory f= new ReactorResourceFactory();
        f.setLoopResources(new LoopResources() {
            @Override
            public EventLoopGroup onServer(boolean b) {
                return eventLoopGroup;
            }
        });
        f.setUseGlobalResources(false);
        return f;
    }

```

We will use this `ReactorResourceFactory` to register a `ReactorClientHttpConnector`:

```java
    @Bean
    public ReactorClientHttpConnector reactorClientHttpConnector(ReactorResourceFactory r) {
        return new ReactorClientHttpConnector(r, m -> m);
    }

```

Finally, anytime we want our `WebClient` to participate in our custom defined thread pool, we can use this bean as the client connector:

```java
    @Bean
    public WebClient webClient(ReactorClientHttpConnector r) {
        return WebClient.builder().baseUrl("http://localhost:9000").clientConnector(r).build();
    }

```
