---
title: "Optimistic Locking in Redis with Reactive Lettuce"
date: 2021-04-24T21:32:36
draft: false
tags: [java, reactive, webflux, lettuce, redis]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Optimistic Locking in Redis is one of the only reasons to want to use transactions, in my opinion. You can ensure a grouping of atomic operations only occur if a watched key does not change out from underneath you. On the CLI, this might start with:

```bash
127.0.0.1:6379&gt; SET key1 value1
OK
127.0.0.1:6379&gt; WATCH key1
OK
127.0.0.1:6379&gt; MULTI
OK

```

WATCH is saying &#34;redis, watch key1 for me, and if it changes at all then rollback the transaction I am about to start.&#34; Then we actually start the transaction with MULTI.

Now on this same thread, let&#39;s say we issue two commands before committing \[before the EXEC, command, that is\]:

```bash
127.0.0.1:6379&gt; SET key2 value2
QUEUED
127.0.0.1:6379&gt; SET key1 newvalue
QUEUED

```

Obviously, because we&#39;re in a transaction, we have not actually &#34;committed&#34; either of these just yet. If we now start up another terminal and run:

```bash
# different shell than the one with the open transaction
127.0.0.1:6379&gt; SET key1 changedbysomeoneelse
OK

```

And then we try to commit the transaction we started above, we can see that it fails and neither operation was successful \[which is the atomicity that we&#39;re looking for\]:

```bash
# shell that has the open transaction
127.0.0.1:6379&gt; EXEC
(nil)
127.0.0.1:6379&gt; GET key2
(nil)
127.0.0.1:6379&gt; GET key1
&#34;changedbysomeoneelse&#34;

```

So that&#39;s what it looks like on the CLI, what does optimistic locking look like in lettuce?

### Optimistic Locking with Reactive Lettuce

As I droned on about my last article on [transactions in redis using lettuce](https://nickolasfisher.com/blog/Redis-Transactions-Reactive-Lettuce-Buyer-Beware), you have to be very careful using any of what follows, but if you&#39;re sure you want to try it here it goes.

To really appreciate what follows, you will want to read that last post, and probably make sure you have something like [a redis test container set up for lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux). We will want to start by creating two connections, then we can start a transaction using one of them:

```java
    @Test
    public void optLocking() {
        RedisReactiveCommands&lt;String, String&gt; firstConnection =
                redisClient.connect().reactive();

        RedisReactiveCommands&lt;String, String&gt; secondConnection =
                redisClient.connect().reactive();

        firstConnection.watch(&#34;key-1&#34;).subscribe();
        firstConnection.multi().subscribe();
    }

```

Similar to the CLI example above, we are first watching &#34;key-1&#34; for any changes, then starting a transaction. If &#34;key-1&#34; is modified by a different process while we execute anything in the following code using that connection, then it will roll back. Here&#39;s some code demonstrating that:

```java
        firstConnection.incr(&#34;key-1&#34;).subscribe();

        secondConnection.set(&#34;key-1&#34;, &#34;10&#34;).subscribe();

        StepVerifier.create(firstConnection.exec())
                // transaction not committed
                .expectNextMatches(tr -&gt; tr.wasDiscarded())
                .verifyComplete();

        StepVerifier.create(secondConnection.get(&#34;key-1&#34;))
                .expectNextMatches(val -&gt; &#34;10&#34;.equals(val))
                .verifyComplete();

```

We increment &#34;key-1&#34; in the existing transaction, then use a different connection \[which is obviously not in the same transaction\] to change that key. When we then try to commit the transaction, redis aborts it on our behalf because that key has already been changed by a different thread.

I would still recommend you find a different way to solve your problem due to the caveats mentioned in that last post, but if you&#39;re intent on doing it, this approach could technically work.
