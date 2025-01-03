---
title: "Optimistic Locking in Redis with Reactive Lettuce"
date: 2021-04-24T21:32:36
draft: false
tags: [java, reactive, webflux, lettuce, redis]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Optimistic Locking in Redis is one of the only reasons to want to use transactions, in my opinion. You can ensure a grouping of atomic operations only occur if a watched key does not change out from underneath you. On the CLI, this might start with:

```bash
127.0.0.1:6379> SET key1 value1
OK
127.0.0.1:6379> WATCH key1
OK
127.0.0.1:6379> MULTI
OK

```

WATCH is saying "redis, watch key1 for me, and if it changes at all then rollback the transaction I am about to start." Then we actually start the transaction with MULTI.

Now on this same thread, let's say we issue two commands before committing \[before the EXEC, command, that is\]:

```bash
127.0.0.1:6379> SET key2 value2
QUEUED
127.0.0.1:6379> SET key1 newvalue
QUEUED

```

Obviously, because we're in a transaction, we have not actually "committed" either of these just yet. If we now start up another terminal and run:

```bash
# different shell than the one with the open transaction
127.0.0.1:6379> SET key1 changedbysomeoneelse
OK

```

And then we try to commit the transaction we started above, we can see that it fails and neither operation was successful \[which is the atomicity that we're looking for\]:

```bash
# shell that has the open transaction
127.0.0.1:6379> EXEC
(nil)
127.0.0.1:6379> GET key2
(nil)
127.0.0.1:6379> GET key1
"changedbysomeoneelse"

```

So that's what it looks like on the CLI, what does optimistic locking look like in lettuce?

### Optimistic Locking with Reactive Lettuce

As I droned on about my last article on [transactions in redis using lettuce](https://nickolasfisher.com/blog/Redis-Transactions-Reactive-Lettuce-Buyer-Beware), you have to be very careful using any of what follows, but if you're sure you want to try it here it goes.

To really appreciate what follows, you will want to read that last post, and probably make sure you have something like [a redis test container set up for lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux). We will want to start by creating two connections, then we can start a transaction using one of them:

```java
    @Test
    public void optLocking() {
        RedisReactiveCommands<String, String> firstConnection =
                redisClient.connect().reactive();

        RedisReactiveCommands<String, String> secondConnection =
                redisClient.connect().reactive();

        firstConnection.watch("key-1").subscribe();
        firstConnection.multi().subscribe();
    }

```

Similar to the CLI example above, we are first watching "key-1" for any changes, then starting a transaction. If "key-1" is modified by a different process while we execute anything in the following code using that connection, then it will roll back. Here's some code demonstrating that:

```java
        firstConnection.incr("key-1").subscribe();

        secondConnection.set("key-1", "10").subscribe();

        StepVerifier.create(firstConnection.exec())
                // transaction not committed
                .expectNextMatches(tr -> tr.wasDiscarded())
                .verifyComplete();

        StepVerifier.create(secondConnection.get("key-1"))
                .expectNextMatches(val -> "10".equals(val))
                .verifyComplete();

```

We increment "key-1" in the existing transaction, then use a different connection \[which is obviously not in the same transaction\] to change that key. When we then try to commit the transaction, redis aborts it on our behalf because that key has already been changed by a different thread.

I would still recommend you find a different way to solve your problem due to the caveats mentioned in that last post, but if you're intent on doing it, this approach could technically work.
