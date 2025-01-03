---
title: "Working with String Types in Redis using Lettuce and Webflux"
date: 2021-04-11T19:01:16
draft: false
tags: [spring, reactive, webflux, lettuce, redis]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

There are, as of this writing, [27 different string operations available in the redis API](https://redis.io/commands/#string). Lettuce appears to have interfaces that directly support all of them.

This article will walk you through some of the more common commands and how to use them against a redis instance.

### Setting up the Test Suite

We're going to build off of previous work where we [set up a redis test container to test lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux), and assuming you have cloned that project and are following along with the right dependencies, I will make a new test class that for now just creates the test container, configured a redis client against that container, and flushes \[removes in redis lingo\] all the data from redis after each test method runs:

```java
@Testcontainers
public class StringTypesTest {

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
            DockerImageName.parse("redis:5.0.3-alpine")
    ).withExposedPorts(6379);

    private RedisClient redisClient;

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

With this in place, we can begin hacking away.

### Set, Get, and Additional Arguments

This is straightforward:

```java
    @Test
    public void setAndGet() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        // vanilla get and set
        StepVerifier.create(redisReactiveCommands.set("some-key-1", "some-value-1"))
                .expectNextMatches(response -> "OK".equals(response)).verifyComplete();

        StepVerifier.create(redisReactiveCommands.get("some-key-1"))
                .expectNextMatches(response -> "some-value-1".equals(response))
                .verifyComplete();

        // adding an additional argument like nx will cause it to return nothing if it doesn't get set
        StepVerifier.create(redisReactiveCommands.set("some-key-1", "some-value-2", new SetArgs().nx()))
                .verifyComplete();

        // prove the value is the same
        StepVerifier.create(redisReactiveCommands.get("some-key-1"))
                .expectNextMatches(response -> "some-value-1".equals(response))
                .verifyComplete();
    }

```

We set **some-key-1** to have **some-value-1**, and verify it's there. We then use the NX argument, which only sets the value if it doesn't exist. We then verify that, because the key was just set, it is not overwritten, by getting it again and asserting the value

### Set NX and Set EX

If we don't like that interface of adding an additional argument for set nx, set ex, etc., then lettuce does provide a slightly more intuitive interface:

```java
    @Test
    public void setNx() throws Exception {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.setnx("key-1", "value-1"))
                .expectNextMatches(success -> success)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.setnx("key-1", "value-2"))
                .expectNextMatches(success -> !success)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.setex("key-1", 1, "value-1"))
                .expectNextMatches(response -> "OK".equals(response))
                .verifyComplete();

        // key-1 expires in 1 second
        Thread.sleep(1500);

        StepVerifier.create(redisReactiveCommands.get("key-1"))
                // no value
                .verifyComplete();
    }

```

We show that trying to set a value that already exists with the nx option fails, and that setting a value with the ex option will indeed expire it within the specified period of time.

### Append

**append** will append a string to an existing string, then return the length of the existing string:

```java
    @Test
    public void append() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.set("key-10", "value-10"))
                .expectNextMatches(response -> "OK".equals(response))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.append("key-10", "-more-stuff"))
                // length of new value is returned
                .expectNextMatches(response -> 19L == response)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.get("key-10"))
                .expectNextMatches(response ->
                        "value-10-more-stuff".equals(response))
                .verifyComplete();
    }

```

We set a key to work with, then append **-more-stuff** to the value, then assert that we get the right length returned and finally make sure the new value looks correct.

### IncrBy

**incrby** increments the value associated with that key by the specified amount. So if the value is 7 and we **incrby** 8, we should get 15:

```java
    @Test
    public void incrBy() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.set("key-counter", "7"))
                .expectNextMatches(response -> "OK".equals(response))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.incrby("key-counter", 8L))
                .expectNextMatches(val -> 15 == val)
                .verifyComplete();
    }

```

Here, we assert exactly that, 7 + 8 is indeed 15 and it is returned to us by redis.

### MGET and MSET

**mset** and **mget** are just the multiples version of **get** and **set**. If we **mset** then we are setting multiple keys at once. If we **mget** then we are getting multiple values from the keys at once:

```java
    @Test
    public void mget() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.mset(Map.of(
                "key-1", "val-1",
                "key-2", "val-2",
                "key-3", "val-3"
        )))
                .expectNextMatches(response -> "OK".equals(response))
                .verifyComplete();

        Flux<KeyValue<String, String>> mgetValuesFlux = redisReactiveCommands.mget("key-1", "key-2", "key-3");
        StepVerifier.create(mgetValuesFlux.collectList())
                .expectNextMatches(collectedValues ->
                        collectedValues.size() == 3
                            &amp;&amp; collectedValues.stream()
                                .anyMatch(stringStringKeyValue ->
                                        stringStringKeyValue.getKey().equals("key-1")
                                                &amp;&amp; stringStringKeyValue.getValue().equals("val-1")
                                )
                )
                .verifyComplete();
    }

```

We set three keys and values in the same command using **mset**, then use **mget** to assert that we do in fact get three keys and values in response. The interface returns a flux, so to simplify it we just collect the flux into a mono containing a list of all the emitted items.

You can feel free to explore the previously linked other string commands that redis exposes via its API, but this should be a good start.
