---
title: "An Introduction to Redis Streams via Lettuce"
date: 2021-05-01T15:22:58
draft: false
tags: [java, reactive, lettuce, redis]
---

The source code for this article [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

[Redis streams](https://redis.io/topics/streams-intro) are an interesting data structure that act as a sort of go-between for list and pub/sub operations: It's like [a list](https://nickolasfisher.com/blog/Working-with-Lists-in-Redis-using-Lettuce-and-Webflux) in the sense that anything pushed onto the stream is retained, it's like [pub/sub](https://nickolasfisher.com/blog/How-to-Publish-and-Subscribe-to-Redis-Using-Lettuce) in the sense that multiple consumers can see what is happening to it. There are many other features of streams that are covered in that article, but that's at least how you can think of it at the start.

Lettuce provides operators that largely line up with what you'd get using the CLI, but here we'll provide a concrete example to eliminate any ambiguity.

### Adding to and Reading From a Stream

We can add to a stream with XADD and read from it with XRANGE. A cli example could look like this:

```bash
$ redis-cli
127.0.0.1:6379> XADD some-stream * first 1 second 2
"1620487924103-0"
127.0.0.1:6379> XLEN some-stream
(integer) 1
127.0.0.1:6379> XRANGE some-stream - +
1) 1) "1620487924103-0"
   2) 1) "first"
      2) "1"
      3) "second"
      4) "2"

```

We add a stream record and let the stream auto assign an ID \[1620487924103-0\] by specifying the " **\***" character. We verify the length of the newly created stream is one, then we look at the item we added.

We can do this in java with lettuce \[note: you will probably want to know [how to set up embedded redis to test a lettuce client](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) to have this make more sense\] like so:

```java
    @Test
    public void streamsEx() throws InterruptedException {
        StepVerifier.create(redisReactiveCommands
                .xadd("some-stream", Map.of("first", "1", "second", "2")))
                .expectNextMatches(resp -> resp.endsWith("-0"))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xlen("some-stream"))
                .expectNext(1L)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xrange("some-stream", Range.create("-", "+")))
                .expectNextMatches(streamMessage ->
                        streamMessage.getBody().get("first").equals("1") &amp;&amp;
                        streamMessage.getBody().get("second").equals("2")
                ).verifyComplete();
    }

```

This is equivalent to what we did with our shell above.

### Subscribing to Stream Elements

We basically just used the stream as a list above, by adding an element to it. We can also treat the stream similar to pub/sub by subscribing to elements as they come in. On the CLI that might look like:

```bash
# writing terminal
127.0.0.1:6379> XADD some-stream * third 3 fourth 4
"1620488397538-0"

# "reading"/"subscribing" terminal
127.0.0.1:6379> XREAD BLOCK 0 STREAMS some-stream $
1) 1) "some-stream"
   2) 1) 1) "1620488397538-0"
         2) 1) "third"
            2) "3"
            3) "fourth"
            4) "4"

```

Building off of our previous work, that equivalent code in lettuce/java might look something like this:

```java
    @Test
    public void streamsEx() throws InterruptedException {
        StepVerifier.create(redisReactiveCommands
                .xadd("some-stream", Map.of("first", "1", "second", "2")))
                .expectNextMatches(resp -> resp.endsWith("-0"))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xlen("some-stream"))
                .expectNext(1L)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.xrange("some-stream", Range.create("-", "+")))
                .expectNextMatches(streamMessage ->
                        streamMessage.getBody().get("first").equals("1") &amp;&amp;
                        streamMessage.getBody().get("second").equals("2")
                ).verifyComplete();

        AtomicInteger elementsSeen = new AtomicInteger(0);
        redisClient.connectPubSub().reactive()
                .xread(
                        new XReadArgs().block(2000),
                        XReadArgs.StreamOffset.from("some-stream", "0")
                )
                .subscribe(stringStringStreamMessage -> {
                    elementsSeen.incrementAndGet();
                });

        StepVerifier.create(redisReactiveCommands
                .xadd("some-stream", Map.of("third", "3", "fourth", "4")))
                .expectNextCount(1)
                .verifyComplete();

        Thread.sleep(500);

        assertEquals(2, elementsSeen.get());
    }

```

We tell **xread** to block as new elements come in, and then verify we receive two elements \[one from before we started subscribing, one from while we were still subscribed\].

From here I encourage you to read [an introduction to streams via redis.io](https://redis.io/topics/streams-intro), and translate what you're reading into unit tests as I have done here.
