---
title: "An Introduction to Redis Streams via Lettuce"
date: 2021-05-01T15:22:58
draft: false
tags: [java, reactive, lettuce, redis]
---

The source code for this article [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

[Redis streams](https://redis.io/topics/streams-intro) are an interesting data structure that act as a sort of go-between for list and pub/sub operations: It&#39;s like [a list](https://nickolasfisher.com/blog/Working-with-Lists-in-Redis-using-Lettuce-and-Webflux) in the sense that anything pushed onto the stream is retained, it&#39;s like [pub/sub](https://nickolasfisher.com/blog/How-to-Publish-and-Subscribe-to-Redis-Using-Lettuce) in the sense that multiple consumers can see what is happening to it. There are many other features of streams that are covered in that article, but that&#39;s at least how you can think of it at the start.

Lettuce provides operators that largely line up with what you&#39;d get using the CLI, but here we&#39;ll provide a concrete example to eliminate any ambiguity.

### Adding to and Reading From a Stream

We can add to a stream with XADD and read from it with XRANGE. A cli example could look like this:

```bash
$ redis-cli
127.0.0.1:6379&gt; XADD some-stream * first 1 second 2
&#34;1620487924103-0&#34;
127.0.0.1:6379&gt; XLEN some-stream
(integer) 1
127.0.0.1:6379&gt; XRANGE some-stream - &#43;
1) 1) &#34;1620487924103-0&#34;
   2) 1) &#34;first&#34;
      2) &#34;1&#34;
      3) &#34;second&#34;
      4) &#34;2&#34;

```

We add a stream record and let the stream auto assign an ID \[1620487924103-0\] by specifying the &#34; **\***&#34; character. We verify the length of the newly created stream is one, then we look at the item we added.

We can do this in java with lettuce \[note: you will probably want to know [how to set up embedded redis to test a lettuce client](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) to have this make more sense\] like so:

```java
    @Test
    public void streamsEx() throws InterruptedException {
        StepVerifier.create(redisReactiveCommands
                .xadd(&#34;some-stream&#34;, Map.of(&#34;first&#34;, &#34;1&#34;, &#34;second&#34;, &#34;2&#34;)))
                .expectNextMatches(resp -&gt; resp.endsWith(&#34;-0&#34;))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xlen(&#34;some-stream&#34;))
                .expectNext(1L)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xrange(&#34;some-stream&#34;, Range.create(&#34;-&#34;, &#34;&#43;&#34;)))
                .expectNextMatches(streamMessage -&gt;
                        streamMessage.getBody().get(&#34;first&#34;).equals(&#34;1&#34;) &amp;&amp;
                        streamMessage.getBody().get(&#34;second&#34;).equals(&#34;2&#34;)
                ).verifyComplete();
    }

```

This is equivalent to what we did with our shell above.

### Subscribing to Stream Elements

We basically just used the stream as a list above, by adding an element to it. We can also treat the stream similar to pub/sub by subscribing to elements as they come in. On the CLI that might look like:

```bash
# writing terminal
127.0.0.1:6379&gt; XADD some-stream * third 3 fourth 4
&#34;1620488397538-0&#34;

# &#34;reading&#34;/&#34;subscribing&#34; terminal
127.0.0.1:6379&gt; XREAD BLOCK 0 STREAMS some-stream $
1) 1) &#34;some-stream&#34;
   2) 1) 1) &#34;1620488397538-0&#34;
         2) 1) &#34;third&#34;
            2) &#34;3&#34;
            3) &#34;fourth&#34;
            4) &#34;4&#34;

```

Building off of our previous work, that equivalent code in lettuce/java might look something like this:

```java
    @Test
    public void streamsEx() throws InterruptedException {
        StepVerifier.create(redisReactiveCommands
                .xadd(&#34;some-stream&#34;, Map.of(&#34;first&#34;, &#34;1&#34;, &#34;second&#34;, &#34;2&#34;)))
                .expectNextMatches(resp -&gt; resp.endsWith(&#34;-0&#34;))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xlen(&#34;some-stream&#34;))
                .expectNext(1L)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xrange(&#34;some-stream&#34;, Range.create(&#34;-&#34;, &#34;&#43;&#34;)))
                .expectNextMatches(streamMessage -&gt;
                        streamMessage.getBody().get(&#34;first&#34;).equals(&#34;1&#34;) &amp;&amp;
                        streamMessage.getBody().get(&#34;second&#34;).equals(&#34;2&#34;)
                ).verifyComplete();

        AtomicInteger elementsSeen = new AtomicInteger(0);
        redisClient.connectPubSub().reactive()
                .xread(
                        new XReadArgs().block(2000),
                        XReadArgs.StreamOffset.from(&#34;some-stream&#34;, &#34;0&#34;)
                )
                .subscribe(stringStringStreamMessage -&gt; {
                    elementsSeen.incrementAndGet();
                });

        StepVerifier.create(redisReactiveCommands
                .xadd(&#34;some-stream&#34;, Map.of(&#34;third&#34;, &#34;3&#34;, &#34;fourth&#34;, &#34;4&#34;)))
                .expectNextCount(1)
                .verifyComplete();

        Thread.sleep(500);

        assertEquals(2, elementsSeen.get());
    }

```

We tell **xread** to block as new elements come in, and then verify we receive two elements \[one from before we started subscribing, one from while we were still subscribed\].

From here I encourage you to read [an introduction to streams via redis.io](https://redis.io/topics/streams-intro), and translate what you&#39;re reading into unit tests as I have done here.
