---
title: "How to Make Concurrent Service API Calls in Java Using Spring Boot"
date: 2019-06-22T20:48:30
draft: false
tags: [java, spring, concurrency]
---

The source code for this post can be found [on GitHub](https://github.com/nfisher23/java-concurrency-examples/tree/master).

When you're in a microservice environment, it often makes sense to make some calls to multiple services at the same time. This allows for the time an operation needs to complete to be reduced from the _sum_ of all the time spent waiting to the _maximum_ time spent over the span of calls.

For example, let's say you make three calls in one service, and let's further say that all three can be called in any order. If:

- Call #1 takes 500ms
- Call #2 takes 700ms
- Call #3 takes 300ms

Then, if you do not make those calls concurrently, then you will have to wait 500 + 700 + 300 = 1500ms. If, however, you make all three at the same time and wait for them to complete before returning, you will only incur the cost of waiting for the longest service. In this case, that is Call #2, and means you will have to wait a total of 700ms.

To demo one way to accomplish this in Spring Boot, we'll start by creating a service that simulates a long running process. We've done something similar to this in the post on [caching in Nginx](https://nickolasfisher.com/blog/how-to-use-nginxs-caching-to-improve-site-responsiveness). Go to the [spring initializr](https://start.spring.io/) and select the "Web" dependency. In the resulting file, change the server port to be on 9000 by modifying the **application.properties**:

```
server.port=9000
```

Then modify the entry point to look like this:

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

This returns a very simple JSON object after a time delay of two seconds, simulating a service that takes awhile to respond.

### Making Concurrent Calls

Now we'll create a service to consume this simple slow server, sending off a few calls and waiting for all of them to complete before returning.

Go back to the spring initializer, and select no additional dependencies. We'll illustrate this with a command line runner.

You will need to add a few to your **pom.xml**, if your using maven:

```xml
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework</groupId>
            <artifactId>spring-web</artifactId>
            <version>5.1.8.RELEASE</version>
        </dependency>

```

We will use the rest template to send calls to the other service, and we will use Jackson to deserialize the response for us.

We will need an [executor](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/concurrent/Executor.html) to spin up threads that our application can use, and we also need to add an **@EnableAsync** annotation to the entrypoint:

```java
@SpringBootApplication
@EnableAsync
public class ConcurrentcallsApplication {

    public static void main(String[] args) {
        SpringApplication.run(ConcurrentcallsApplication.class, args);
    }

    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }

    @Bean
    public Executor executor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(5);
        executor.setMaxPoolSize(5);
        executor.setQueueCapacity(500);
        executor.initialize();
        return executor;
    }

}

```

We can then create a service class that will make calls to our other, "slow" microservice:

```java
@Service
public class SlowServiceCaller {

    @Autowired
    private RestTemplate restTemplate;

    @Async
    public CompletableFuture<JsonNode> callOtherService() {
        String localSlowServiceEndpoint = "http://localhost:9000/slow";
        JsonNode responseObj = restTemplate.getForObject(localSlowServiceEndpoint, JsonNode.class);
        return CompletableFuture.completedFuture(responseObj);
    }
}

```

With this configuration, Spring will inject a proxy for every time **SlowServiceCaller.callOtherService()** is called, ensuring that the previously defined **Executor** is responsible for executing the calls. As long as we return a **CompletableFuture** here, it doesn't necessarily matter what we do. This could be a database query, this could be a compute-intensive process using in memory data, or any other potentially long running process. Here, obviously, we're firing off a network call.

To demonstrate this, we'll fire up a **CommandLineRunner** like so:

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

Now, if you are sure to start up the slow service from before, you should see five calls get made in a batch, then another five calls after the threads release.

What do we expect to see here? Well, we have 5 threads in this process, and we know that the endpoint we are hitting will take about two seconds to respond. So, we should see a total time to completion of 4 seconds. Indeed, my stdout shows:

```
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
response: {"hello":"hello"}
Total time: 4

```

**Further Suggested Reading:**

- [Async Calls in Spring Boot](https://spring.io/guides/gs/async-method/)
