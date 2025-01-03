---
title: "The Difference Between a Reactive Non-Blocking Model and Classic Asynchronous Code"
date: 2019-07-06T15:10:01
draft: false
tags: [java, spring, concurrency, reactive]
---

Reactive Programming is a very different way of thinking about doing work in a microservices environment. Anyone who has worked with a GUI, dating back to even to windows forms, is familiar with the event based model, but what does that mean when there is unpredictable latency involved? How does handing off to a thread to make a remote call differ from this new "reactive web"?

This was confusing to me at first, so I dug in and got a solid example working to illustrate what's really going on here.

### Some Background On Theory

Reactive Programming across network boundaries is fundamentally different from just making asynchronous calls in exactly one way. We'll start with an example from a [previous blog post on making concurrent API calls in Spring Boot](https://nickolasfisher.com/blog/How-to-Make-Concurrent-Service-API-Calls-in-Java-Using-Spring-Boot). In that example, the primary block to consider was this:

```java
@Component
public class ConcurrentRunner implements CommandLineRunner {

    @Autowired
    SlowServiceCaller slowServiceCaller;

    @Override
    public void run(String... args) throws Exception {
        Instant start = Instant.now();
        List<CompletableFuture<JsonNode>> allFutures = new ArrayList<>();

        for (int i = 0; i < 10; i++) {
            allFutures.add(slowServiceCaller.callOtherService());
        }

        CompletableFuture.allOf(allFutures.toArray(new CompletableFuture[0])).join();

        for (int i = 0; i < 10; i++) {
            System.out.println("response: " + allFutures.get(i).get().toString());
        }

        System.out.println("Total time: " + Duration.between(start, Instant.now()).getSeconds());
    }
}

```

When configured with an Executor of 5 threads, and hitting an endpoint that takes exactly 2 seconds to resolve and respond, the whole operation takes 4 seconds. This is roughly what happens:

1. `slowServiceCaller.callOtherService()` hands off the REST API call to a thread, which is pulled from an `Executor` \[a thread pool\]
2. The thread that gets handed the task will make a call to the remote service
3. After the call has completed \[the TCP layer will require some chatter back and forth to make sure that the message gets there properly, and if there is TLS involved there will be a handshake back and forth\], the thread will sit there and wait for a response for however long it has been configured to timeout. This is called _blocking_.
4. Once the response gets in, which will involve more TCP layer chatter to validate the correct message gets there, the thread processes it, drops it into a `CompletableFuture`, and then releases.

This is asynchronous, and blocking. Each thread that gets a task will have to wait, in this case two seconds each time, until the service it is calling can send the message back.

Reactive programming basically came out of this realization: This thread we're handing off to is spending the vast majority of its time _waiting_, and doing _nothing_. It sends the request, then waits for a much longer period of time, then eventually gets a response and continues work.

So, what if we could design a model where our threads were always working? What would that look like? Well, one way to do it would be to have each thread focus on sending the request, then immediately rejoining the work pool. When the response comes in, we can generate an event that either that thread or another thread can pick up, and process the response. That is the reactive model in a nutshell: we try to make sure that our threads are always working on something, and not waiting.

### An Example

From that previous blog post, make sure that you have a slow service that we can interact with. In a nutshell, the endpoint we'll hit can look like this:

```java
@SpringBootApplication
@RestController
public class SlowApplication {

    public static void main(String[] args) {
        SpringApplication.run(SlowApplication.class, args);
    }

    @GetMapping("/slow")
    public String slow() throws InterruptedException {
        Thread.sleep(2000);
        return "{\"hello\":\"hello\"}";
    }
}

```

If we have this service running on **port 9000**, then we can configure a reactive `WebClient` to use that as a base url. Going off a previous post on [configuring Reactive Netty in Spring Boot](https://nickolasfisher.com/blog/How-to-Configure-Reactive-Netty-in-Spring-Boot-in-Depth), we can modify our event loop group to have just five threads:

```java
    @Bean
    public NioEventLoopGroup nioEventLoopGroup() {
        return new NioEventLoopGroup(5);
    }

    @Bean
    public WebClient webClient(ReactorClientHttpConnector r) {
        // root url to localhost:9000, where our slow service should be running
        return WebClient.builder().baseUrl("http://localhost:9000").clientConnector(r).build();
    }

```

We can then implement a command line runner. In this case, we'll have it loop one thousand times:

```java
@Component
public class ReactiveCallsRunner implements CommandLineRunner {

    private static Logger logger = LoggerFactory.getLogger(ReactiveCallsRunner.class);

    @Autowired
    WebClient webClient;

    @Override
    public void run(String... args) throws Exception {
        for (int i = 0; i < 1000; i++) {
            webClient.get().uri("/slow").accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .bodyToMono(JsonNode.class)
                    .doOnSuccess(jsonNode -> logger.info("thread: " + Thread.currentThread()))
                    .subscribe();
        }

        logger.info("done with command line runner");
    }
}

```

Before we run this, what do we expect to see? Well, the service that we are hitting is running on an embedded Tomcat webserver. In Spring Boot, that defaults to 200 threads. Because we know that our reactive `WebClient` is nonblocking, five threads should be able to send out all of the requests at once, but the client that we are hitting will max out at 200 responses every two seconds. Therefore, all of the calls should complete within about ten seconds or so.

If you run this:

```bash
$ mvn spring-boot:run

```

Then, assuming your slow service is up and running on port 9000, your logs should start like this:

```
08:44:07.981  INFO 25590 --- [           main] c.n.reactiveex.ReactiveCallsRunner       : done with command line runner
08:44:09.959  INFO 25590 --- [ntLoopGroup-2-3] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-3,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.959  INFO 25590 --- [ntLoopGroup-2-2] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-2,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.959  INFO 25590 --- [ntLoopGroup-2-4] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-4,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.959  INFO 25590 --- [ntLoopGroup-2-1] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-1,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.959  INFO 25590 --- [ntLoopGroup-2-5] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-5,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.962  INFO 25590 --- [ntLoopGroup-2-5] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-5,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.962  INFO 25590 --- [ntLoopGroup-2-2] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-2,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.962  INFO 25590 --- [ntLoopGroup-2-3] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-3,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.962  INFO 25590 --- [ntLoopGroup-2-4] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-4,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.962  INFO 25590 --- [ntLoopGroup-2-1] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-1,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.963  INFO 25590 --- [ntLoopGroup-2-5] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-5,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.963  INFO 25590 --- [ntLoopGroup-2-2] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-2,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.964  INFO 25590 --- [ntLoopGroup-2-3] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-3,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.964  INFO 25590 --- [ntLoopGroup-2-4] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-4,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.964  INFO 25590 --- [ntLoopGroup-2-1] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-1,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.964  INFO 25590 --- [ntLoopGroup-2-5] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-5,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.964  INFO 25590 --- [ntLoopGroup-2-2] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-2,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.965  INFO 25590 --- [ntLoopGroup-2-3] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-3,10,com.nickolasfisher.reactiveex.ReactiveexApplication]
08:44:09.965  INFO 25590 --- [ntLoopGroup-2-5] c.n.reactiveex.ReactiveCallsRunner       : thread: Thread[nioEventLoopGroup-2-5,10,com.nickolasfisher.reactiveex.ReactiveexApplication]

```

We can see that we are reusing the same five threads, and that all of these calls go out within about 5 milliseconds of each other. This is where the real advantage of reactive web comes into play: when you have latency and it's unpredictable, then this kind of architecture will still be consistent.

Even if you set the thread pool size to 1, we can still send out 1000 requests in under a few hundred milliseconds, despite the fact that the service we're calling takes two seconds to respond.
