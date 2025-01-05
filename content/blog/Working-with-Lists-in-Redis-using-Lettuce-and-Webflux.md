---
title: "Working with Lists in Redis using Lettuce and Webflux"
date: 2021-04-11T21:14:08
draft: false
tags: [distributed systems, spring, reactive, webflux, lettuce, redis]
---

As of this writing, there are a solid [twenty or so commands you can execute against redis for the list data type](https://redis.io/commands/#list). This article will be walking through some of the more common operations you are likely to need when interacting with redis and lists using lettuce, and [the source code can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Building off of a previous post where we [set up a redis test container for testing lettuce](https://nickolasfisher.com/blog/how-to-use-a-redis-test-container-with-lettucespring-boot-webflux), we can take that setup and teardown code and make it a base abstract class for reuse:

```java
@Testcontainers
public abstract class BaseSetupAndTeardownRedis {

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
            DockerImageName.parse("redis:5.0.3-alpine")
    ).withExposedPorts(6379);

    protected RedisClient redisClient;

    @BeforeEach
    public void setupRedisClient() {
        redisClient = RedisClient.create("redis://" + genericContainer.getHost() + ":" + genericContainer.getMappedPort(6379));
    }

    @AfterEach
    public void removeAllDataFromRedis() {
        redisClient.connect().reactive().flushall().block();
    }
}

```

This just starts our redis container, configures our redis client to communicate with it by default, then deletes all the data out of redis after each test case has run. With this in place, we can start writing some test cases demonstrating how we can interact with lists in redis.

### Push and Pop

One of the more common things you're likely to do against redis lists is just adding and removing elements from the "left" or "right". We'll demonstrate how to remove from the left here:

```java
    @Test
    public void addAndRemoveFromTheLeft() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.lpush("list-key", "fourth-element", "third-element"))
                .expectNextMatches(sizeOfList -> 2L == sizeOfList)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.lpush("list-key","second-element", "first-element"))
                // pushes to the left of the same list
                .expectNextMatches(sizeOfList -> 4L == sizeOfList)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.lpop("list-key"))
                .expectNextMatches(poppedElement -> "first-element".equals(poppedElement))
                .verifyComplete();
    }

```

We insert elements four, three, two, then one from left to right. This leads to a list that looks like **first-element -> second-element -> third-element -> fourth-element**. we then pop an element off the "left" of the list to grab the first element, then verify that is indeed what we're getting.

### Blocking Get

This one is more interesting. The **blpop** operation will block until an element becomes available \[for a specified number of seconds\]. If one doesn't become available in time, it will release itself. Here's an example where we execute a **blpop** and we then push an element into the list about half a second later, asserting that the amount of time that took was at least half a second \[ _ish_. I made it 400 ms mostly out of paranoia\]:

```java
    @Test
    public void blockingGet() {
        RedisReactiveCommands<String, String> redisReactiveCommands1 = redisClient.connect().reactive();
        RedisReactiveCommands<String, String> redisReactiveCommands2 = redisClient.connect().reactive();

        long startingTime = Instant.now().toEpochMilli();
        StepVerifier.create(Mono.zip(
                    redisReactiveCommands1.blpop(1, "list-key").switchIfEmpty(Mono.just(KeyValue.empty("list-key"))),
                    Mono.delay(Duration.ofMillis(500)).then(redisReactiveCommands2.lpush("list-key", "an-element"))
                ).map(tuple -> tuple.getT1().getValue())
            )
            .expectNextMatches(value -> "an-element".equals(value))
            .verifyComplete();
        long endingTime = Instant.now().toEpochMilli();

        assertTrue(endingTime - startingTime > 400);
    }

```

### Range of Elements

If you want to just look at any given range of elements, you can do that with **lrange**. This command will iterate from left to right and pull out elements as it finds them between the indices that you specify:

```java
    @Test
    public void getRange() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.lpush("list-key", "third-element", "second-element", "first-element"))
                .expectNextMatches(sizeOfList -> 3L == sizeOfList)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.lrange("list-key", 0, 1))
                .expectNextMatches(first -> "first-element".equals(first))
                .expectNextMatches(second -> "second-element".equals(second))
                .verifyComplete();
    }

```

It's important to note that for very large lists, this operation could take more time than you would like, because redis lists are implemented as linked lists. Therefore getting elements towards the middle of the list will be a `O(N)` operation.
