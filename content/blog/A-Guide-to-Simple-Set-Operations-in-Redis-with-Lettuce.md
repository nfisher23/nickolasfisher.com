---
title: "A Guide to Simple Set Operations in Redis with Lettuce"
date: 2021-04-17T08:09:37
draft: false
---

There are, as of this writing, about [15 distinct operations available to someone wanting to work with sets in redis](https://redis.io/commands/#set). This article seeks to cover some of the more basic ones using a reactive lettuce client, and [a follow up article](https://nickolasfisher.com/blog/A-Guide-to-Operating-on-Multiple-Sets-in-Redis-with-Lettuce) will seek to deal with explaining some of the more common operations against multiple sets, rather than a single set in this case.

To start with, you&#39;ll want to make sure that you have either [setup a redis test container for a lettuce client](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux) or [setup embedded redis for a lettuce client](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux), which will make this article much easier to follow along with. The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

### sadd, smembers, srem

The first thing we&#39;ll cover is adding elements to a set, viewing the members in that set, and removing elements from that set.

**sadd** adds elements to a set only if they don&#39;t already exist, and returns the number of elements in a set that were added, **smembers** returns all the elements, and **srem** removes elements only if they exist, returning the number that was removed:

```java
    @Test
    public void sAdd_and_sRem() {
        String setKey = &#34;set-key-1&#34;;
        Mono&lt;Long&gt; saddMono = redisReactiveCommands.sadd(setKey, &#34;value-1&#34;, &#34;value-2&#34;);

        StepVerifier.create(saddMono)
                .expectNextMatches(numberOfElementsAdded -&gt; 2L == numberOfElementsAdded)
                .verifyComplete();

        Mono&lt;Long&gt; saddOneRepeatingValueMono = redisReactiveCommands.sadd(setKey, &#34;value-1&#34;, &#34;value-3&#34;);

        StepVerifier.create(saddOneRepeatingValueMono)
                .expectNextMatches(numberOfElementsAdded -&gt; 1L == numberOfElementsAdded)
                .verifyComplete();

        Mono&lt;List&lt;String&gt;&gt; smembersCollectionMono = redisReactiveCommands.smembers(setKey).collectList();

        StepVerifier.create(smembersCollectionMono)
                .expectNextMatches(setMembers -&gt; setMembers.size() == 3 &amp;&amp; setMembers.contains(&#34;value-3&#34;))
                .verifyComplete();

        Mono&lt;Long&gt; sremValue3Mono = redisReactiveCommands.srem(setKey, &#34;value-3&#34;);

        StepVerifier.create(sremValue3Mono)
                .expectNextMatches(numRemoved -&gt; numRemoved == 1L)
                .verifyComplete();

        StepVerifier.create(smembersCollectionMono)
                .expectNextMatches(setMembers -&gt; setMembers.size() == 2 &amp;&amp; !setMembers.contains(&#34;value-3&#34;));
    }

```

This code is pretty straightforward, we&#39;re adding an element that already exists \[&#34;value-1&#34;\] and one that doesn&#39;t \[&#34;value-3&#34;\] in the original set, so we see 1 element added in the response. We then view the members, remove an element \[&#34;value-3&#34;\], then view the members again. We make assertions every step of that way and this test passes those assertions.

### sismember

Another operation you&#39;re likely to care quite a bit about is **sismember**. This operation tells you whether an element exists in the set and is an O\[1\] operation:

```java
    @Test
    public void sisMember() {
        String setKey = &#34;set-key-1&#34;;
        Mono&lt;Long&gt; saddMono = redisReactiveCommands.sadd(setKey, &#34;value-1&#34;, &#34;value-2&#34;);

        StepVerifier.create(saddMono)
                .expectNextMatches(numberOfElementsAdded -&gt; 2L == numberOfElementsAdded)
                .verifyComplete();

        Mono&lt;Boolean&gt; shouldNotExistInSetMono = redisReactiveCommands.sismember(setKey, &#34;value-3&#34;);

        StepVerifier.create(shouldNotExistInSetMono)
                .expectNext(false)
                .verifyComplete();

        Mono&lt;Boolean&gt; shouldExistInSetMono = redisReactiveCommands.sismember(setKey, &#34;value-2&#34;);

        StepVerifier.create(shouldExistInSetMono)
                .expectNext(true)
                .verifyComplete();
    }

```

Here we add two elements to a set to start with \[&#34;value-1&#34; and &#34;value-2&#34;\], then verify that using **sismember** does indeed verify that an element not in the set returns **false**, then an element that is actually in the set returns **true**.

And with that, you should be good to go.
