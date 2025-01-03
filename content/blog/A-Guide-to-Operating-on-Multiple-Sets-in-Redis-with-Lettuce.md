---
title: "A Guide to Operating on Multiple Sets in Redis with Lettuce"
date: 2021-04-01T00:00:00
draft: false
---

In the last article, we showed how to do some of the most common single set operations against redis, this article will focus on operating on multiple sets using a lettuce client against redis. Specifically, we&#39;ll focus on subtracting, intersecting, and adding sets. The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

### Subtracting Sets

Subtracting sets work similarly to subtracting numbers.

You take the first set, and when there are elements in the second set that match the element in the first set, you take those out of the set that you return. Both the set you&#39;re subtracting from and the set you&#39;re using to subtract will remain unchanged.

``` java
    @Test
    public void subtractingMultipleSets() {
        String firstSetKey = &#34;first-set-key&#34;;
        String secondSetKey = &#34;second-set-key&#34;;
        Mono&lt;Long&gt; setupFirstSetMono = redisReactiveCommands.sadd(firstSetKey, &#34;value-1&#34;, &#34;value-2&#34;);

        StepVerifier.create(setupFirstSetMono).expectNext(2L).verifyComplete();

        Mono&lt;Long&gt; setupSecondSetMono = redisReactiveCommands.sadd(secondSetKey, &#34;value-1&#34;, &#34;value-3&#34;);

        StepVerifier.create(setupSecondSetMono).expectNext(2L).verifyComplete();

        Mono&lt;List&lt;String&gt;&gt; subtractSecondFromFirstCollection = redisReactiveCommands.sdiff(firstSetKey, secondSetKey).collectList();

        StepVerifier.create(subtractSecondFromFirstCollection)
                .expectNextMatches(collection -&gt;
                        collection.size() == 1
                        &amp;&amp; collection.contains(&#34;value-2&#34;))
                .verifyComplete();

        Mono&lt;List&lt;String&gt;&gt; subtractFirstFromSecondCollection = redisReactiveCommands.sdiff(secondSetKey, firstSetKey).collectList();

        StepVerifier.create(subtractFirstFromSecondCollection)
                .expectNextMatches(collection -&gt;
                        collection.size() == 1
                                &amp;&amp; collection.contains(&#34;value-3&#34;))
                .verifyComplete();

        Mono&lt;List&lt;String&gt;&gt; originalSetUnchangedMono = redisReactiveCommands.smembers(firstSetKey).collectList();

        StepVerifier.create(originalSetUnchangedMono)
                .expectNextMatches(firstSetMembers -&gt;
                        firstSetMembers.size() == 2
                        &amp;&amp; firstSetMembers.contains(&#34;value-1&#34;)
                        &amp;&amp; firstSetMembers.contains(&#34;value-2&#34;)
                ).verifyComplete();
    }

```

Here, we create two sets, subtract them in both directions, then verify the original set was unchanged. This test passes.

### Intersecting Sets

Intersecting sets in redis means that only elements that are in both sets make it into the resulting set. You use **sinter** to intersect two different sets:

``` java
    @Test
    public void intersectingMultipleSets() {
        String firstSetKey = &#34;first-set-key&#34;;
        String secondSetKey = &#34;second-set-key&#34;;
        Mono&lt;Long&gt; setupFirstSetMono = redisReactiveCommands
                .sadd(firstSetKey, &#34;value-1&#34;, &#34;value-2&#34;);

        StepVerifier.create(setupFirstSetMono).expectNext(2L).verifyComplete();

        Mono&lt;Long&gt; setupSecondSetMono = redisReactiveCommands
                .sadd(secondSetKey, &#34;value-1&#34;, &#34;value-3&#34;);

        StepVerifier.create(setupSecondSetMono).expectNext(2L).verifyComplete();

        Mono&lt;List&lt;String&gt;&gt; intersectedSets = redisReactiveCommands
                .sinter(firstSetKey, secondSetKey).collectList();

        StepVerifier.create(intersectedSets)
                .expectNextMatches(collection -&gt;
                    collection.size() == 1
                        &amp;&amp; collection.contains(&#34;value-1&#34;)
                        &amp;&amp; !collection.contains(&#34;value-2&#34;)
                )
                .verifyComplete();
    }

```

&#34;first-set-key&#34; and &#34;second-set-key&#34; only share &#34;value-1&#34; as a common element, so the intersected set contains only one element \[&#34;value-1&#34;\].

### Adding Sets

Adding sets \[also called a **union**\] is basically the same as if you were to get all the members of both sets, then run **sadd** over and over again. Common elements only show up once because that&#39;s how sets work:

``` java
    @Test
    public void addingMultipleSetsTogether() {
        String firstSetKey = &#34;first-set-key&#34;;
        String secondSetKey = &#34;second-set-key&#34;;
        Mono&lt;Long&gt; setupFirstSetMono = redisReactiveCommands
                .sadd(firstSetKey, &#34;value-1&#34;, &#34;value-2&#34;);

        StepVerifier.create(setupFirstSetMono).expectNext(2L).verifyComplete();

        Mono&lt;Long&gt; setupSecondSetMono = redisReactiveCommands
                .sadd(secondSetKey, &#34;value-1&#34;, &#34;value-3&#34;);

        StepVerifier.create(setupSecondSetMono).expectNext(2L).verifyComplete();

        Mono&lt;List&lt;String&gt;&gt; unionedSets = redisReactiveCommands
                .sunion(firstSetKey, secondSetKey).collectList();

        StepVerifier.create(unionedSets)
                .expectNextMatches(collection -&gt;
                    collection.size() == 3
                        &amp;&amp; collection.contains(&#34;value-1&#34;)
                        &amp;&amp; collection.contains(&#34;value-2&#34;)
                        &amp;&amp; collection.contains(&#34;value-3&#34;)
                )
                .verifyComplete();
    }

```

The identical sets we&#39;ve been creating for every test so far are here added together, which leads to a three element set of &#34;value-1&#34;, &#34;value-2&#34;, and &#34;value-3&#34;.

And with that, you should be good to go.


