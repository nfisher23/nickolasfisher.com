---
title: "A Guide to Operating on Multiple Sets in Redis with Lettuce"
date: 2021-04-17T08:12:31
draft: false
tags: [java, spring, reactive, webflux, lettuce, redis]
---

In the last article, we showed how to do some of the most common single set operations against redis, this article will focus on operating on multiple sets using a lettuce client against redis. Specifically, we'll focus on subtracting, intersecting, and adding sets. The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

### Subtracting Sets

Subtracting sets work similarly to subtracting numbers.

You take the first set, and when there are elements in the second set that match the element in the first set, you take those out of the set that you return. Both the set you're subtracting from and the set you're using to subtract will remain unchanged.

```java
    @Test
    public void subtractingMultipleSets() {
        String firstSetKey = "first-set-key";
        String secondSetKey = "second-set-key";
        Mono<Long> setupFirstSetMono = redisReactiveCommands.sadd(firstSetKey, "value-1", "value-2");

        StepVerifier.create(setupFirstSetMono).expectNext(2L).verifyComplete();

        Mono<Long> setupSecondSetMono = redisReactiveCommands.sadd(secondSetKey, "value-1", "value-3");

        StepVerifier.create(setupSecondSetMono).expectNext(2L).verifyComplete();

        Mono<List<String>> subtractSecondFromFirstCollection = redisReactiveCommands.sdiff(firstSetKey, secondSetKey).collectList();

        StepVerifier.create(subtractSecondFromFirstCollection)
                .expectNextMatches(collection ->
                        collection.size() == 1
                        &amp;&amp; collection.contains("value-2"))
                .verifyComplete();

        Mono<List<String>> subtractFirstFromSecondCollection = redisReactiveCommands.sdiff(secondSetKey, firstSetKey).collectList();

        StepVerifier.create(subtractFirstFromSecondCollection)
                .expectNextMatches(collection ->
                        collection.size() == 1
                                &amp;&amp; collection.contains("value-3"))
                .verifyComplete();

        Mono<List<String>> originalSetUnchangedMono = redisReactiveCommands.smembers(firstSetKey).collectList();

        StepVerifier.create(originalSetUnchangedMono)
                .expectNextMatches(firstSetMembers ->
                        firstSetMembers.size() == 2
                        &amp;&amp; firstSetMembers.contains("value-1")
                        &amp;&amp; firstSetMembers.contains("value-2")
                ).verifyComplete();
    }

```

Here, we create two sets, subtract them in both directions, then verify the original set was unchanged. This test passes.

### Intersecting Sets

Intersecting sets in redis means that only elements that are in both sets make it into the resulting set. You use **sinter** to intersect two different sets:

```java
    @Test
    public void intersectingMultipleSets() {
        String firstSetKey = "first-set-key";
        String secondSetKey = "second-set-key";
        Mono<Long> setupFirstSetMono = redisReactiveCommands
                .sadd(firstSetKey, "value-1", "value-2");

        StepVerifier.create(setupFirstSetMono).expectNext(2L).verifyComplete();

        Mono<Long> setupSecondSetMono = redisReactiveCommands
                .sadd(secondSetKey, "value-1", "value-3");

        StepVerifier.create(setupSecondSetMono).expectNext(2L).verifyComplete();

        Mono<List<String>> intersectedSets = redisReactiveCommands
                .sinter(firstSetKey, secondSetKey).collectList();

        StepVerifier.create(intersectedSets)
                .expectNextMatches(collection ->
                    collection.size() == 1
                        &amp;&amp; collection.contains("value-1")
                        &amp;&amp; !collection.contains("value-2")
                )
                .verifyComplete();
    }

```

"first-set-key" and "second-set-key" only share "value-1" as a common element, so the intersected set contains only one element \["value-1"\].

### Adding Sets

Adding sets \[also called a **union**\] is basically the same as if you were to get all the members of both sets, then run **sadd** over and over again. Common elements only show up once because that's how sets work:

```java
    @Test
    public void addingMultipleSetsTogether() {
        String firstSetKey = "first-set-key";
        String secondSetKey = "second-set-key";
        Mono<Long> setupFirstSetMono = redisReactiveCommands
                .sadd(firstSetKey, "value-1", "value-2");

        StepVerifier.create(setupFirstSetMono).expectNext(2L).verifyComplete();

        Mono<Long> setupSecondSetMono = redisReactiveCommands
                .sadd(secondSetKey, "value-1", "value-3");

        StepVerifier.create(setupSecondSetMono).expectNext(2L).verifyComplete();

        Mono<List<String>> unionedSets = redisReactiveCommands
                .sunion(firstSetKey, secondSetKey).collectList();

        StepVerifier.create(unionedSets)
                .expectNextMatches(collection ->
                    collection.size() == 3
                        &amp;&amp; collection.contains("value-1")
                        &amp;&amp; collection.contains("value-2")
                        &amp;&amp; collection.contains("value-3")
                )
                .verifyComplete();
    }

```

The identical sets we've been creating for every test so far are here added together, which leads to a three element set of "value-1", "value-2", and "value-3".

And with that, you should be good to go.
