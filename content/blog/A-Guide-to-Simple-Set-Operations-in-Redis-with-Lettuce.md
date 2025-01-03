---
title: "A Guide to Simple Set Operations in Redis with Lettuce"
date: 2021-04-17T08:09:37
draft: false
tags: [java, spring, reactive, webflux, lettuce, redis]
---

There are, as of this writing, about [15 distinct operations available to someone wanting to work with sets in redis](https://redis.io/commands/#set). This article seeks to cover some of the more basic ones using a reactive lettuce client, and [a follow up article](https://nickolasfisher.com/blog/A-Guide-to-Operating-on-Multiple-Sets-in-Redis-with-Lettuce) will seek to deal with explaining some of the more common operations against multiple sets, rather than a single set in this case.

To start with, you'll want to make sure that you have either [setup a redis test container for a lettuce client](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux) or [setup embedded redis for a lettuce client](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux), which will make this article much easier to follow along with. The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

### sadd, smembers, srem

The first thing we'll cover is adding elements to a set, viewing the members in that set, and removing elements from that set.

**sadd** adds elements to a set only if they don't already exist, and returns the number of elements in a set that were added, **smembers** returns all the elements, and **srem** removes elements only if they exist, returning the number that was removed:

```java
    @Test
    public void sAdd_and_sRem() {
        String setKey = "set-key-1";
        Mono<Long> saddMono = redisReactiveCommands.sadd(setKey, "value-1", "value-2");

        StepVerifier.create(saddMono)
                .expectNextMatches(numberOfElementsAdded -> 2L == numberOfElementsAdded)
                .verifyComplete();

        Mono<Long> saddOneRepeatingValueMono = redisReactiveCommands.sadd(setKey, "value-1", "value-3");

        StepVerifier.create(saddOneRepeatingValueMono)
                .expectNextMatches(numberOfElementsAdded -> 1L == numberOfElementsAdded)
                .verifyComplete();

        Mono<List<String>> smembersCollectionMono = redisReactiveCommands.smembers(setKey).collectList();

        StepVerifier.create(smembersCollectionMono)
                .expectNextMatches(setMembers -> setMembers.size() == 3 &amp;&amp; setMembers.contains("value-3"))
                .verifyComplete();

        Mono<Long> sremValue3Mono = redisReactiveCommands.srem(setKey, "value-3");

        StepVerifier.create(sremValue3Mono)
                .expectNextMatches(numRemoved -> numRemoved == 1L)
                .verifyComplete();

        StepVerifier.create(smembersCollectionMono)
                .expectNextMatches(setMembers -> setMembers.size() == 2 &amp;&amp; !setMembers.contains("value-3"));
    }

```

This code is pretty straightforward, we're adding an element that already exists \["value-1"\] and one that doesn't \["value-3"\] in the original set, so we see 1 element added in the response. We then view the members, remove an element \["value-3"\], then view the members again. We make assertions every step of that way and this test passes those assertions.

### sismember

Another operation you're likely to care quite a bit about is **sismember**. This operation tells you whether an element exists in the set and is an O\[1\] operation:

```java
    @Test
    public void sisMember() {
        String setKey = "set-key-1";
        Mono<Long> saddMono = redisReactiveCommands.sadd(setKey, "value-1", "value-2");

        StepVerifier.create(saddMono)
                .expectNextMatches(numberOfElementsAdded -> 2L == numberOfElementsAdded)
                .verifyComplete();

        Mono<Boolean> shouldNotExistInSetMono = redisReactiveCommands.sismember(setKey, "value-3");

        StepVerifier.create(shouldNotExistInSetMono)
                .expectNext(false)
                .verifyComplete();

        Mono<Boolean> shouldExistInSetMono = redisReactiveCommands.sismember(setKey, "value-2");

        StepVerifier.create(shouldExistInSetMono)
                .expectNext(true)
                .verifyComplete();
    }

```

Here we add two elements to a set to start with \["value-1" and "value-2"\], then verify that using **sismember** does indeed verify that an element not in the set returns **false**, then an element that is actually in the set returns **true**.

And with that, you should be good to go.
