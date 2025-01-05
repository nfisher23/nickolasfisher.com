---
title: "How to use a Redis Test Container with Lettuce/Spring Boot Webflux"
date: 2021-03-27T23:52:07
draft: false
tags: [java, spring, testing, webflux, lettuce, redis]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/reactive-redis).

Another way to write integration tests for code that verifies your interactions with redis actually make sense is to use a [test container](https://www.testcontainers.org/). This framework assumes you have docker up and running, but if you do it will pull a specified container image \[typically you'll just use docker hub, though it's important to note that they rate limit you, so don't go overboard\], then you can interact with that container in your integration tests.

Here, we'll use a redis test container to write an integration test for some redis code in spring boot webflux, using lettuce as the underlying redis client driver.

Let's start by leveraging code written from a previous post where we [use embedded redis to write integration tests for lettuce](https://nickolasfisher.com/blog/how-to-use-embedded-redis-to-test-a-lettuce-client-in-spring-boot-webflux) instead of a container. The key piece of code is the actual data class which looks like this:

```java
public class RedisDataService {

    private final RedisStringReactiveCommands<String, String> redisStringReactiveCommands;

    public RedisDataService(RedisStringReactiveCommands<String, String> redisStringReactiveCommands) {
        this.redisStringReactiveCommands = redisStringReactiveCommands;
    }

    public Mono<Void> writeThing(Thing thing) {
        return this.redisStringReactiveCommands
                .set(thing.getId().toString(), thing.getValue())
                .then();
    }

    public Mono<Thing> getThing(Integer id) {
        return this.redisStringReactiveCommands.get(id.toString())
                .map(response -> Thing.builder().id(id).value(response).build());
    }
}

```

This is a super simple class that just uses an integer as a key and the "value" field in **Thing** as the value. It sets values in redis and it gets them from redis.

We will want to add the test containers maven dependency before we get to using it, somewhat obviously:

```xml
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>testcontainers</artifactId>
            <version>1.15.2</version>
            <scope>test</scope>
        </dependency>

```

Now with that in place, let's get to writing the test. The key difference here is that test containers is actually going to be handling choosing a random open port for us, and mapping that port to the underlying redis database running inside that container. So one way to do it looks like this:

```java
public class RedisTestContainerTest {
    private static GenericContainer genericContainer;
    private RedisDataService redisDataService;

    @BeforeAll
    public static void setupRedisServer() {
         genericContainer = new GenericContainer(
                 DockerImageName.parse("redis:5.0.3-alpine")
            ).withExposedPorts(6379);
         genericContainer.start();
    }

    @BeforeEach
    public void setupRedisClient() {
        RedisClient redisClient = RedisClient.create("redis://" + genericContainer.getHost() + ":" + genericContainer.getMappedPort(6379));
        redisDataService = new RedisDataService(redisClient.connect().reactive());
    }

    @Test
    public void canWriteAndReadThing() {
        Mono<Void> writeMono = redisDataService.writeThing(Thing.builder().id(1).value("hello-redis").build());

        StepVerifier.create(writeMono).verifyComplete();

        StepVerifier.create(redisDataService.getThing(1))
                .expectNextMatches(thing ->
                        thing.getId() == 1 &amp;&amp;
                                "hello-redis".equals(thing.getValue())
                )
                .verifyComplete();
    }

    @AfterAll
    public static void teardownRedisServer() {
        genericContainer.stop();
    }
}

```

The important line in here, and what makes it work, is that we defer to the host and port that **genericContainer** is managing for us. But there is one way we can improve this, which is to leverage a special type of **ClassRule**, one provided by test containers itself and available for junit 5. First, we will need one more dependency:

```xml
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>1.15.2</version>
            <scope>test</scope>
        </dependency>

```

Then we can modify our code like so:

```java
@Testcontainers
public class RedisTestContainerTest {

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
                DockerImageName.parse("redis:5.0.3-alpine")
            ).withExposedPorts(6379);

    private RedisDataService redisDataService;

    @BeforeEach
    public void setupRedisClient() {
        RedisClient redisClient = RedisClient.create("redis://" + genericContainer.getHost() + ":" + genericContainer.getMappedPort(6379));
        redisDataService = new RedisDataService(redisClient.connect().reactive());
    }

    @Test
    public void canWriteAndReadThing() {
        Mono<Void> writeMono = redisDataService.writeThing(Thing.builder().id(1).value("hello-redis").build());

        StepVerifier.create(writeMono).verifyComplete();

        StepVerifier.create(redisDataService.getThing(1))
                .expectNextMatches(thing ->
                        thing.getId() == 1 &amp;&amp;
                                "hello-redis".equals(thing.getValue())
                )
                .verifyComplete();
    }
}

```

And you should be good to go.
