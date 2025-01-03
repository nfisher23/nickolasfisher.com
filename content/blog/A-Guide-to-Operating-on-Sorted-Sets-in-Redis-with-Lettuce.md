---
title: "A Guide to Operating on Sorted Sets in Redis with Lettuce"
date: 2021-04-01T00:00:00
draft: false
---

Sorted Sets in redis are one of my personal favorite tools when operating at scale. As of this writing, [there are over 30 unique operations you can perform against sorted sets in redis](https://redis.io/commands/#sorted_set). This article will focus on some of the more common ones you&#39;re going to need to know, and it will use a reactive lettuce client to demonstrate them.

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

### Adding and Updating Sorted Sets

A sorted set can be thought of as a set with a score. The elements are sorted according to their score, and if the scores match then it will then use lexicographical ordering of the elements itself. Two elements can&#39;t be in the same position because a set does not allow multiple elements.

To add to a set, you need to specify the score, and to update the score for an element in the set, you run the exact same command \[&#34;add&#34;\]. Here is an example:

``` java
    @Test
    public void zAddAndUpdate() {
        String setKey = &#34;set-key-1&#34;;
        Mono&lt;Long&gt; addOneHundredScoreMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(100, &#34;one hundred&#34;));

        StepVerifier.create(addOneHundredScoreMono)
                .expectNextMatches(numAdded -&gt; 1L == numAdded).verifyComplete();

        Mono&lt;Double&gt; getOneHundredScoreMono = redisReactiveCommands.zscore(setKey, &#34;one hundred&#34;);

        StepVerifier.create(getOneHundredScoreMono)
                .expectNextMatches(score -&gt; score &lt; 100.01 &amp;&amp; score &gt; 99.99)
                .verifyComplete();

        Mono&lt;Double&gt; elementDoesNotExistMono = redisReactiveCommands.zscore(setKey, &#34;not here&#34;);

        StepVerifier.create(elementDoesNotExistMono)
                .verifyComplete();

        Mono&lt;Long&gt; updateOneHundredScoreMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(105, &#34;one hundred&#34;));

        StepVerifier.create(updateOneHundredScoreMono)
                // updated, not added, so 0
                .expectNextMatches(numAdded -&gt; 0L == numAdded)
                .verifyComplete();

        StepVerifier.create(getOneHundredScoreMono)
                .expectNextMatches(score -&gt; score &lt; 105.01 &amp;&amp; score &gt; 104.99)
                .verifyComplete();
    }

```

Here, we&#39;re adding an element to a sorted set \[the set is created when the first element is added, and if you remove the last element in a set then the set will be destroyed automatically\] with a score of 100. We are later updating the same element \[the element with value &#34;one hundred&#34;\] to have a score of 105. Because a score is a double value \[and those can operate a bit unpredictably--i.e. lose their &#34;exact&#34; value\], I&#39;m asserting that the score equals what it&#39;s supposed to by checking that it&#39;s between two other double values.

### Retrieving a Range of Elements and Scores

It&#39;s a common need to get a range \[in this case, all elements\] of elements in a sorted set and return their scores along with the elements:

``` java
    @Test
    public void zRange_Rank_AndScore() {
        String setKey = &#34;set-key-1&#34;;
        Mono&lt;Long&gt; addOneHundredScoreMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(100, &#34;one hundred&#34;));

        StepVerifier.create(addOneHundredScoreMono)
                .expectNextMatches(numAdded -&gt; 1L == numAdded).verifyComplete();

        Mono&lt;List&lt;ScoredValue&lt;String&gt;&gt;&gt; allCollectedElementsMono = redisReactiveCommands
                .zrangebyscoreWithScores(setKey, Range.unbounded()).collectList();

        StepVerifier.create(allCollectedElementsMono)
                .expectNextMatches(allElements -&gt; allElements.size() == 1
                                &amp;&amp; allElements.stream().allMatch(
                        scoredValue -&gt; scoredValue.getScore() == 100
                                &amp;&amp; scoredValue.getValue().equals(&#34;one hundred&#34;)
                        )
                ).verifyComplete();

        Mono&lt;Long&gt; addFiftyMono = redisReactiveCommands.zadd(setKey, ScoredValue.just(50, &#34;fifty&#34;));

        StepVerifier.create(addFiftyMono)
                .expectNextMatches(numAdded -&gt; 1L == numAdded)
                .verifyComplete();

        // by default, lowest score is at the front, or zero index
        StepVerifier.create(allCollectedElementsMono)
                .expectNextMatches(
                        allElements -&gt; allElements.size() == 2
                                &amp;&amp; allElements.get(0).equals(ScoredValue.just(50, &#34;fifty&#34;))
                                &amp;&amp; allElements.get(1).equals(ScoredValue.just(100, &#34;one hundred&#34;))
                ).verifyComplete();
    }

```

We&#39;re using **zrangebyscoreWIthScores** to get a collection of elements and their scores. Because we&#39;re not actually filtering out any elements \[because we used **Range.unbounded**\], this is effectively the same as us using **smembers** against a vanilla set, except now we are getting the score associated with the element instead of just the element itself. It&#39;s important to note that, by default, any elements that are returned from a sorted set are sorted with the lowest score &#34;first,&#34; or in the 0th place in the collection.

### Removing a Range of Elements by Score

As the title of this section states, we also might want to remove any section of a sorted set based on a range of scores. To accomplish that, we will want to use **zremrangebyscore**:

``` java
    @Test
    public void zRevRangeByScore() {
        String setKey = &#34;set-key-1&#34;;
        Mono&lt;Long&gt; addOneHundredScoreMono = redisReactiveCommands
                .zadd(
                        setKey,
                        ScoredValue.just(100, &#34;first&#34;),
                        ScoredValue.just(200, &#34;second&#34;),
                        ScoredValue.just(300, &#34;third&#34;)
                );

        StepVerifier.create(addOneHundredScoreMono)
                .expectNextMatches(numAdded -&gt; 3L == numAdded).verifyComplete();

        Mono&lt;Long&gt; removeElementsByScoreMono = redisReactiveCommands
                .zremrangebyscore(setKey, Range.create(90, 210));

        StepVerifier.create(removeElementsByScoreMono)
                .expectNext(2L)
                .verifyComplete();

        Mono&lt;List&lt;ScoredValue&lt;String&gt;&gt;&gt; allCollectedElementsMono = redisReactiveCommands
                .zrangebyscoreWithScores(setKey, Range.unbounded()).collectList();

        StepVerifier.create(allCollectedElementsMono)
                .expectNextMatches(allElements -&gt; allElements.size() == 1
                                &amp;&amp; allElements.stream().allMatch(
                        scoredValue -&gt; scoredValue.getScore() == 300
                                &amp;&amp; scoredValue.getValue().equals(&#34;third&#34;)
                        )
                ).verifyComplete();
    }

```

Here we&#39;re dropping any elements with score between 90 and 210, which in this specific case will just be the &#34;first&#34; and &#34;second&#34; elements which have been given scores of 100 and 200, respectively.


