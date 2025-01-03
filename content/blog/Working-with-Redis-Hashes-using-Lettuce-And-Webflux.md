---
title: "Working with Redis Hashes using Lettuce And Webflux"
date: 2021-04-11T22:26:29
draft: false
tags: [java, spring, reactive, webflux, lettuce, redis]
---

There are about [15 or so commands you can execute against redis for hash types](https://redis.io/commands/#hash) as of this writing. This article will demonstrate some of the more common operations you're likely to need when using lettuce as your client.

To start with, you're going to want to make sure you have either an [embedded redis instance configured with lettuce](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) or a [redis test container configured for lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux), which will make what follows much more straightforward to grok. And the source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Hashes in redis are basically just objects. There's a key to get to the object, then buried within that initial key are a bunch of other keys that point to values. Another way to think of hashes are a key that points to a bunch of key/value pairs, all of which are string values.

### Set and Get All

The easiest way to get started is to set a hash object and then get all of those key/value pairs:

```java
public class HashesTest extends BaseSetupAndTeardownRedis {

    @Test
    public void setSingleHashAndGetWholeHash() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        Mono<String> multiSetMono = redisReactiveCommands.hmset("hash-set-key", Map.of(
                "key-1", "value-1",
                "key-2", "value-2",
                "key-3", "value-3"
        ));

        StepVerifier.create(multiSetMono)
                .expectNextMatches(response -> "OK".equals(response))
                .verifyComplete();

        Mono<List<KeyValue<String, String>>> allKeyValuesMono = redisReactiveCommands.hgetall("hash-set-key").collectList();

        StepVerifier.create(allKeyValuesMono)
                .expectNextMatches(keyValues -> keyValues.size() == 3
                    &amp;&amp; keyValues.stream()
                        .anyMatch(keyValue -> keyValue.getValue().equals("value-2")
                                &amp;&amp; keyValue.getKey().equals("key-2"))
                )
                .verifyComplete();
    }
}

```

Note that the **BaseSetupAndTeardownRedis** abstract base class does what it says it does: sets up redis and tears it down when we're done. For details on how that works, you can refer to the related post about [working with list data types in redis using lettuce](https://nickolasfisher.com/blog/Working-with-Lists-in-Redis-using-Lettuce-and-Webflux).

The above example shows that we can set key/value pairs inside of our key. In this case we set three values, we then use a method that enumerates all the key/value pairs inside of our previously defined hash set and asserts that they were set up correctly.

### Getting and Setting Individual Fields

The real value of hashes are going to come from manipulating individual fields inside of the hash. For example, let's start with the same set of data we did in the previous example:

```java
    @Test
    public void getAndSetSingleValueInHash() {
        RedisReactiveCommands<String, String> redisReactiveCommands = redisClient.connect().reactive();

        Mono<String> multiSetMono = redisReactiveCommands.hmset("hash-set-key", Map.of(
                "key-1", "value-1",
                "key-2", "value-2",
                "key-3", "value-3"
        ));

        StepVerifier.create(multiSetMono)
                .expectNextMatches(response -> "OK".equals(response))
                .verifyComplete();
    }

```

We can then set and get individual fields inside of that hash set with something like this:

```java
        StepVerifier.create(redisReactiveCommands.hget("hash-set-key", "key-1"))
                .expectNextMatches(val -> val.equals("value-1"))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.hset("hash-set-key", "key-2", "new-value-2"))
                // returns false if no new fields were added--in this case we're changing an existing field
                .expectNextMatches(response -> !response)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.hget("hash-set-key", "key-2"))
                .expectNextMatches(val -> "new-value-2".equals(val))
                .verifyComplete();

        // different value in the same hash is unchanged
        StepVerifier.create(redisReactiveCommands.hget("hash-set-key", "key-1"))
                .expectNextMatches(val -> "value-1".equals(val))
                .verifyComplete();

```

We get **key-1**, then change the value under **key-2**, then we verify that both the value under **key-2** was changed, but also that the value under our **key-1** was left unchanged.

While there are many more operations available to you \[linked at the top of this article\], you should be in pretty good shape after this introduction, and I'll leave you to it.
