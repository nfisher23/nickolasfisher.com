---
title: "How to Publish and Subscribe to Redis Using Lettuce"
date: 2021-04-01T00:00:00
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Subscribing to topics in redis allows for a _fanout_ behavior, where any number of subscribers can be notified of a message from a publisher.

With the cli, you can simply run:

``` bash
redis-cli subscribe some-channel
Reading messages... (press Ctrl-C to quit)
1) &#34;subscribe&#34;
2) &#34;some-channel&#34;
3) (integer) 1

```

Then, in another terminal, we can:

``` bash
redis-cli publish some-channel some-message
(integer) 1

```

And we will see in the original terminal where we&#39;re still subscribed:

``` bash
1) &#34;message&#34;
2) &#34;some-channel&#34;
3) &#34;some-message&#34;

```

In java using lettuce, the process is pretty similar, but subscribing is a little wonky.

### Publish/Subscribe with Lettuce

For a fast feedback loop, you can refer to either using [embedded redis to test lettuce](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) or [using a redis test container to test lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux) as a starting point. Once that&#39;s in place, subscribing and publishing looks like this:

``` java
    @Test
    public void publishAndSubscribe() throws Exception {
        StatefulRedisPubSubConnection&lt;String, String&gt; pubSubConnection =
                redisClient.connectPubSub();

        AtomicBoolean messageReceived = new AtomicBoolean(false);
        RedisPubSubReactiveCommands&lt;String, String&gt; reactivePubSubCommands = pubSubConnection.reactive();
        reactivePubSubCommands.subscribe(&#34;some-channel&#34;).subscribe();

        reactivePubSubCommands.observeChannels()
                .doOnNext(stringStringChannelMessage -&gt; messageReceived.set(true))
                .subscribe();

        Thread.sleep(25);

        redisClient.connectPubSub()
                .reactive()
                .publish(&#34;some-channel&#34;, &#34;some-message&#34;)
                .subscribe();

        Thread.sleep(25);

        Assertions.assertTrue(messageReceived.get());
    }

```

The gist of the code is that we publish to the channel after we subscribe, and verify that we actually received a message by asserting that an **AtomicBoolean** was flipped to true. This test passes.


