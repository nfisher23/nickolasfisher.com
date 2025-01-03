---
title: "How to Publish and Subscribe to Redis Using Lettuce"
date: 2021-04-24T16:37:18
draft: false
tags: [java, spring, reactive, webflux, lettuce, redis]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Subscribing to topics in redis allows for a _fanout_ behavior, where any number of subscribers can be notified of a message from a publisher.

With the cli, you can simply run:

```bash
redis-cli subscribe some-channel
Reading messages... (press Ctrl-C to quit)
1) "subscribe"
2) "some-channel"
3) (integer) 1

```

Then, in another terminal, we can:

```bash
redis-cli publish some-channel some-message
(integer) 1

```

And we will see in the original terminal where we're still subscribed:

```bash
1) "message"
2) "some-channel"
3) "some-message"

```

In java using lettuce, the process is pretty similar, but subscribing is a little wonky.

### Publish/Subscribe with Lettuce

For a fast feedback loop, you can refer to either using [embedded redis to test lettuce](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) or [using a redis test container to test lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux) as a starting point. Once that's in place, subscribing and publishing looks like this:

```java
    @Test
    public void publishAndSubscribe() throws Exception {
        StatefulRedisPubSubConnection<String, String> pubSubConnection =
                redisClient.connectPubSub();

        AtomicBoolean messageReceived = new AtomicBoolean(false);
        RedisPubSubReactiveCommands<String, String> reactivePubSubCommands = pubSubConnection.reactive();
        reactivePubSubCommands.subscribe("some-channel").subscribe();

        reactivePubSubCommands.observeChannels()
                .doOnNext(stringStringChannelMessage -> messageReceived.set(true))
                .subscribe();

        Thread.sleep(25);

        redisClient.connectPubSub()
                .reactive()
                .publish("some-channel", "some-message")
                .subscribe();

        Thread.sleep(25);

        Assertions.assertTrue(messageReceived.get());
    }

```

The gist of the code is that we publish to the channel after we subscribe, and verify that we actually received a message by asserting that an **AtomicBoolean** was flipped to true. This test passes.
