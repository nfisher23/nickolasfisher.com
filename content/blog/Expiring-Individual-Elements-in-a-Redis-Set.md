---
title: "Expiring Individual Elements in a Redis Set"
date: 2021-04-18T20:13:11
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Redis does not allow you to set the expiration on individual members in a set, it only allows you to set an expiration on the entire set itself. If you want to have a sort of expiry on individual elements in a set, this article shares a workaround to that problem that works well in practice. Because I have already written a lot of [boilerplate code for testing any redis operation using lettuce](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux), I&#39;m going to be showing you this technique using a reactive lettuce client, however the basic concept should transfer easily to any other client.

### Use A Sorted Set

To start with, instead of using a vanilla set, we&#39;re going to use a sorted set where the score of each element is the current epoch timestamp, represented in this example using the number of milliseconds since epoch \[here&#39;s [an introduction to sorted sets in redis using lettuce](https://nickolasfisher.com/blog/A-Guide-to-Operating-on-Sorted-Sets-in-Redis-with-Lettuce) for those not sure how to follow along just yet\].

So let&#39;s add three entries in our sorted set, sleeping for 100 milliseconds in between adding each one, and every time we add an element we specify the **score** as the current number of milliseconds since epoch:

```java
    @Test
    public void expireElementsPeriodically() throws Exception {
        String setKey = &#34;values-set-key&#34;;

        addValueToSet(setKey, &#34;first&#34;);
        Thread.sleep(100);

        addValueToSet(setKey, &#34;second&#34;);
        Thread.sleep(100);

        addValueToSet(setKey, &#34;third&#34;);
        Thread.sleep(100);
    }

    private void addValueToSet(String setKey, String value) {
        Mono&lt;Long&gt; addValueWithEpochMilliScore = redisReactiveCommands.zadd(setKey, ScoredValue.just(Instant.now().toEpochMilli(), value));

        StepVerifier.create(addValueWithEpochMilliScore)
                .expectNext(1L)
                .verifyComplete();
    }

```

Now you&#39;ll have three entries in the set \[&#34;first&#34;, &#34;second&#34;, and &#34;third&#34;\]. Each entry will have a score that is the epoch millisecond timestamp of when it was entered. It&#39;s important to note that redis doesn&#39;t know that--it just keeps the entries sorted by an arbitrary score. If we want to expire them, we now just have to issue one command, which is to pick a time that we consider entries in the set to be invalid and remove them by score:

```java
        // expire everything older than 250ms ago
        Mono&lt;Long&gt; expireOldEntriesMono = redisReactiveCommands.zremrangebyscore(setKey,
                Range.create(0, Instant.now().minus(250, ChronoUnit.MILLIS).toEpochMilli())
        );

        StepVerifier.create(expireOldEntriesMono)
                .expectNext(1L).verifyComplete();

        // get all entries
        StepVerifier.create(redisReactiveCommands.zrevrangebyscore(setKey, Range.unbounded()))
                .expectNextMatches(val -&gt; &#34;third&#34;.equals(val))
                .expectNextMatches(val -&gt; &#34;second&#34;.equals(val))
                .verifyComplete();

```

Here we&#39;re expiring everything older than 250ms ago, which should just delete our first entry since it&#39;s been 300 milliseconds since we put it in there.

### A Better Approach

In the above example, we didn&#39;t _really_ set the expiry of every element in the set. What we did was specify when we put the element in there, and then later decided what was &#34;too old&#34; for us at some future date. A better way to do this would be to make the score associated with each element to be the _actual time it should expire_, then periodically remove entries older than right now:

```java
    @Test
    public void expireElementsPeriodically() throws Exception {
        String setKey = &#34;values-set-key&#34;;

        addValueToSet(setKey, &#34;first&#34;, Instant.now().plus(450, ChronoUnit.MILLIS).toEpochMilli());
        Thread.sleep(100);

        addValueToSet(setKey, &#34;second&#34;, Instant.now().plus(150, ChronoUnit.MILLIS).toEpochMilli());
        Thread.sleep(100);

        addValueToSet(setKey, &#34;third&#34;, Instant.now().plus(500, ChronoUnit.MILLIS).toEpochMilli());
        Thread.sleep(100);

        // expire everything based on score, or time to expire as epoch millisecond
        Mono&lt;Long&gt; expireOldEntriesMono = redisReactiveCommands.zremrangebyscore(setKey,
                Range.create(0, Instant.now().toEpochMilli())
        );

        StepVerifier.create(expireOldEntriesMono)
                .expectNext(1L).verifyComplete();

        // get all entries
        StepVerifier.create(redisReactiveCommands.zrevrangebyscore(setKey, Range.unbounded()))
                .expectNextMatches(val -&gt; &#34;third&#34;.equals(val))
                .expectNextMatches(val -&gt; &#34;first&#34;.equals(val))
                .verifyComplete();
    }

    private void addValueToSet(String setKey, String value, long epochMilliToExpire) {
        Mono&lt;Long&gt; addValueWithEpochMilliScore = redisReactiveCommands.zadd(
                setKey,
                ScoredValue.just(epochMilliToExpire, value)
        );

        StepVerifier.create(addValueWithEpochMilliScore)
                .expectNext(1L)
                .verifyComplete();
    }

```

This approach is probably going to be more intuitive than deciding on behalf of the entire set what needs to be expired.
