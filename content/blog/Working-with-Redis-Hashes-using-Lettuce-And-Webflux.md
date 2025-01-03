---
title: "Working with Redis Hashes using Lettuce And Webflux"
date: 2021-04-11T22:26:29
draft: false
---

There are about [15 or so commands you can execute against redis for hash types](https://redis.io/commands/#hash) as of this writing. This article will demonstrate some of the more common operations you&#39;re likely to need when using lettuce as your client.

To start with, you&#39;re going to want to make sure you have either an [embedded redis instance configured with lettuce](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) or a [redis test container configured for lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux), which will make what follows much more straightforward to grok. And the source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Hashes in redis are basically just objects. There&#39;s a key to get to the object, then buried within that initial key are a bunch of other keys that point to values. Another way to think of hashes are a key that points to a bunch of key/value pairs, all of which are string values.

### Set and Get All

The easiest way to get started is to set a hash object and then get all of those key/value pairs:

```java
public class HashesTest extends BaseSetupAndTeardownRedis {

    @Test
    public void setSingleHashAndGetWholeHash() {
        RedisReactiveCommands&lt;String, String&gt; redisReactiveCommands = redisClient.connect().reactive();

        Mono&lt;String&gt; multiSetMono = redisReactiveCommands.hmset(&#34;hash-set-key&#34;, Map.of(
                &#34;key-1&#34;, &#34;value-1&#34;,
                &#34;key-2&#34;, &#34;value-2&#34;,
                &#34;key-3&#34;, &#34;value-3&#34;
        ));

        StepVerifier.create(multiSetMono)
                .expectNextMatches(response -&gt; &#34;OK&#34;.equals(response))
                .verifyComplete();

        Mono&lt;List&lt;KeyValue&lt;String, String&gt;&gt;&gt; allKeyValuesMono = redisReactiveCommands.hgetall(&#34;hash-set-key&#34;).collectList();

        StepVerifier.create(allKeyValuesMono)
                .expectNextMatches(keyValues -&gt; keyValues.size() == 3
                    &amp;&amp; keyValues.stream()
                        .anyMatch(keyValue -&gt; keyValue.getValue().equals(&#34;value-2&#34;)
                                &amp;&amp; keyValue.getKey().equals(&#34;key-2&#34;))
                )
                .verifyComplete();
    }
}

```

Note that the **BaseSetupAndTeardownRedis** abstract base class does what it says it does: sets up redis and tears it down when we&#39;re done. For details on how that works, you can refer to the related post about [working with list data types in redis using lettuce](https://nickolasfisher.com/blog/Working-with-Lists-in-Redis-using-Lettuce-and-Webflux).

The above example shows that we can set key/value pairs inside of our key. In this case we set three values, we then use a method that enumerates all the key/value pairs inside of our previously defined hash set and asserts that they were set up correctly.

### Getting and Setting Individual Fields

The real value of hashes are going to come from manipulating individual fields inside of the hash. For example, let&#39;s start with the same set of data we did in the previous example:

```java
    @Test
    public void getAndSetSingleValueInHash() {
        RedisReactiveCommands&lt;String, String&gt; redisReactiveCommands = redisClient.connect().reactive();

        Mono&lt;String&gt; multiSetMono = redisReactiveCommands.hmset(&#34;hash-set-key&#34;, Map.of(
                &#34;key-1&#34;, &#34;value-1&#34;,
                &#34;key-2&#34;, &#34;value-2&#34;,
                &#34;key-3&#34;, &#34;value-3&#34;
        ));

        StepVerifier.create(multiSetMono)
                .expectNextMatches(response -&gt; &#34;OK&#34;.equals(response))
                .verifyComplete();
    }

```

We can then set and get individual fields inside of that hash set with something like this:

```java
        StepVerifier.create(redisReactiveCommands.hget(&#34;hash-set-key&#34;, &#34;key-1&#34;))
                .expectNextMatches(val -&gt; val.equals(&#34;value-1&#34;))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.hset(&#34;hash-set-key&#34;, &#34;key-2&#34;, &#34;new-value-2&#34;))
                // returns false if no new fields were added--in this case we&#39;re changing an existing field
                .expectNextMatches(response -&gt; !response)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.hget(&#34;hash-set-key&#34;, &#34;key-2&#34;))
                .expectNextMatches(val -&gt; &#34;new-value-2&#34;.equals(val))
                .verifyComplete();

        // different value in the same hash is unchanged
        StepVerifier.create(redisReactiveCommands.hget(&#34;hash-set-key&#34;, &#34;key-1&#34;))
                .expectNextMatches(val -&gt; &#34;value-1&#34;.equals(val))
                .verifyComplete();

```

We get **key-1**, then change the value under **key-2**, then we verify that both the value under **key-2** was changed, but also that the value under our **key-1** was left unchanged.

While there are many more operations available to you \[linked at the top of this article\], you should be in pretty good shape after this introduction, and I&#39;ll leave you to it.
