---
title: "A Guide to Operating on Sorted Sets in Redis with Lettuce"
date: 2021-04-17T08:15:31
draft: false
tags: [java, spring, webflux, lettuce, redis]
---

Sorted Sets in redis are one of my personal favorite tools when operating at scale. As of this writing, [there are over 30 unique operations you can perform against sorted sets in redis](https://redis.io/commands/#sorted_set). This article will focus on some of the more common ones you're going to need to know, and it will use a reactive lettuce client to demonstrate them.

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

### Adding and Updating Sorted Sets

A sorted set can be thought of as a set with a score. The elements are sorted according to their score, and if the scores match then it will then use lexicographical ordering of the elements itself. Two elements can't be in the same position because a set does not allow multiple elements.

To add to a set, you need to specify the score, and to update the score for an element in the set, you run the exact same command \["add"\]. Here is an example:

```java
    @Test
    public void zAddAndUpdate() {
        String setKey = "set-key-1";
        Mono<Long> addOneHundredScoreMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(100, "one hundred"));

        StepVerifier.create(addOneHundredScoreMono)
                .expectNextMatches(numAdded -> 1L == numAdded).verifyComplete();

        Mono<Double> getOneHundredScoreMono = redisReactiveCommands.zscore(setKey, "one hundred");

        StepVerifier.create(getOneHundredScoreMono)
                .expectNextMatches(score -> score < 100.01 &amp;&amp; score > 99.99)
                .verifyComplete();

        Mono<Double> elementDoesNotExistMono = redisReactiveCommands.zscore(setKey, "not here");

        StepVerifier.create(elementDoesNotExistMono)
                .verifyComplete();

        Mono<Long> updateOneHundredScoreMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(105, "one hundred"));

        StepVerifier.create(updateOneHundredScoreMono)
                // updated, not added, so 0
                .expectNextMatches(numAdded -> 0L == numAdded)
                .verifyComplete();

        StepVerifier.create(getOneHundredScoreMono)
                .expectNextMatches(score -> score < 105.01 &amp;&amp; score > 104.99)
                .verifyComplete();
    }

```

Here, we're adding an element to a sorted set \[the set is created when the first element is added, and if you remove the last element in a set then the set will be destroyed automatically\] with a score of 100. We are later updating the same element \[the element with value "one hundred"\] to have a score of 105. Because a score is a double value \[and those can operate a bit unpredictably--i.e. lose their "exact" value\], I'm asserting that the score equals what it's supposed to by checking that it's between two other double values.

### Retrieving a Range of Elements and Scores

It's a common need to get a range \[in this case, all elements\] of elements in a sorted set and return their scores along with the elements:

```java
    @Test
    public void zRange_Rank_AndScore() {
        String setKey = "set-key-1";
        Mono<Long> addOneHundredScoreMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(100, "one hundred"));

        StepVerifier.create(addOneHundredScoreMono)
                .expectNextMatches(numAdded -> 1L == numAdded).verifyComplete();

        Mono<List<ScoredValue<String>>> allCollectedElementsMono = redisReactiveCommands
                .zrangebyscoreWithScores(setKey, Range.unbounded()).collectList();

        StepVerifier.create(allCollectedElementsMono)
                .expectNextMatches(allElements -> allElements.size() == 1
                                &amp;&amp; allElements.stream().allMatch(
                        scoredValue -> scoredValue.getScore() == 100
                                &amp;&amp; scoredValue.getValue().equals("one hundred")
                        )
                ).verifyComplete();

        Mono<Long> addFiftyMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(50, "fifty"));

        StepVerifier.create(addFiftyMono)
                .expectNextMatches(numAdded -> 1L == numAdded)
                .verifyComplete();

        // by default, lowest score is at the front, or zero index
        StepVerifier.create(allCollectedElementsMono)
                .expectNextMatches(
                        allElements -> allElements.size() == 2
                                &amp;&amp; allElements.get(0).equals(ScoredValue.just(50, "fifty"))
                                &amp;&amp; allElements.get(1).equals(ScoredValue.just(100, "one hundred"))
                ).verifyComplete();
    }

```

We're using **zrangebyscoreWIthScores** to get a collection of elements and their scores. Because we're not actually filtering out any elements \[because we used **Range.unbounded**\], this is effectively the same as us using **smembers** against a vanilla set, except now we are getting the score associated with the element instead of just the element itself. It's important to note that, by default, any elements that are returned from a sorted set are sorted with the lowest score "first," or in the 0th place in the collection.

### Removing a Range of Elements by Score

As the title of this section states, we also might want to remove any section of a sorted set based on a range of scores. To accomplish that, we will want to use **zremrangebyscore**:

```java
    @Test
    public void zRevRangeByScore() {
        String setKey = "set-key-1";
        Mono<Long> addOneHundredScoreMono = redisReactiveCommands
                .zadd(
                        setKey,
                        ScoredValue.just(100, "first"),
                        ScoredValue.just(200, "second"),
                        ScoredValue.just(300, "third")
                );

        StepVerifier.create(addOneHundredScoreMono)
                .expectNextMatches(numAdded -> 3L == numAdded).verifyComplete();

        Mono<Long> removeElementsByScoreMono = redisReactiveCommands
                .zremrangebyscore(setKey, Range.create(90, 210));

        StepVerifier.create(removeElementsByScoreMono)
                .expectNext(2L)
                .verifyComplete();

        Mono<List<ScoredValue<String>>> allCollectedElementsMono = redisReactiveCommands
                .zrangebyscoreWithScores(setKey, Range.unbounded()).collectList();

        StepVerifier.create(allCollectedElementsMono)
                .expectNextMatches(allElements -> allElements.size() == 1
                                &amp;&amp; allElements.stream().allMatch(
                        scoredValue -> scoredValue.getScore() == 300
                                &amp;&amp; scoredValue.getValue().equals("third")
                        )
                ).verifyComplete();
    }

```

Here we're dropping any elements with score between 90 and 210, which in this specific case will just be the "first" and "second" elements which have been given scores of 100 and 200, respectively.
