---
title: "Using Redis as a Distributed Lock with Lettuce"
date: 2021-05-01T14:44:31
draft: false
---

The source code for this article [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Using Redis as a best effort locking mechanism can be very useful in practice, to prevent two logical threads from clobbering each other. While redis locking is certainly not perfect, and [you shouldn&#39;t use redis locking if the underlying operation can&#39;t be occasionally done twice](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html), it can still be useful for that &#34;best effort, do this once&#34; use case.

### Basic Order of Operations

The non edge case scenario can look like:

1. Atomically acquire a lock with a timeout
2. Get a boolean response: Lock acquired/Lock not acquired
3. If lock acquired, do your work
4. If lock not acquired, do nothing

There are some key edge cases we&#39;ll want to pay attention to, but this is the gist of it.

### Naive Implementation

Note: it will be much easier to follow along if you know [how to configure embedded redis to test a reactive lettuce client](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) or [how to configure a test container to test a redis client](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux).

A simple implementation of our problem can look like this:

```java
    public Mono&lt;Void&gt; simpleDoIfLockAcquired(String lockKey, Mono&lt;Void&gt; thingToDo) {
        return redisReactiveCommands.setnx(lockKey, &#34;ACQUIRED&#34;)
                .flatMap(acquired -&gt; {
                    if (acquired) {
                        System.out.println(&#34;lock acquired, returning mono&#34;);
                        return thingToDo;
                    } else {
                        System.out.println(&#34;lock not acquired, doing nothing&#34;);
                        return Mono.empty();
                    }
                });
    }

```

Here, we&#39;re using SETNX to atomically write a key with a value to redis. If the write fails, SETNX will tell us that is failed. We can pass in any operation \[represented as a Mono\] that we want to be performed. Here&#39;s an example using it and verifying we don&#39;t do anything twice in the normal use case:

```java
    @Test
    public void distributedLocking() {
        AtomicInteger numTimesCalled = new AtomicInteger(0);
        Mono&lt;Void&gt; justLogItMono = Mono.defer(() -&gt; {
            System.out.println(&#34;not doing anything, just logging&#34;);
            numTimesCalled.incrementAndGet();
            return Mono.empty();
        });

        StepVerifier.create(simpleDoIfLockAcquired(&#34;lock-123&#34;, justLogItMono))
                .verifyComplete();

        StepVerifier.create(simpleDoIfLockAcquired(&#34;lock-123&#34;, justLogItMono))
                .verifyComplete();

        StepVerifier.create(simpleDoIfLockAcquired(&#34;lock-123&#34;, justLogItMono))
                .verifyComplete();

        assertEquals(1, numTimesCalled.get());
    }

```

This test counts the number of times our **justLogItMono** actually gets invoked, and because we use the same locking key every time, it only gets invoked once.

### Handling Edge Cases

We have a couple of problems with the above implementation, however.

For one, we have no timeout on that lock--so if the underlying thing that we&#39;re doing fails unexpectedly, it never gets done. For two, we have no way of saying whether we&#39;re currently processing the underlying operation or whether we have already finished it, or processed it \[which is useful if another thread comes along later, because then that thread knows to abandon the operation completely rather than wait until the lease expires\]. Finally, if there are any errors when doing the underlying operation, ideally we would just release the lock right away so another thread could retry when the time comes.

We can improve upon this situation with some code like the following:

```java
    public Mono&lt;Void&gt; doIfLockAcquiredAndHandleErrors(String lockKey, Mono&lt;Void&gt; thingToDo) {
        SetArgs setArgs = new SetArgs().nx().ex(20);
        return redisReactiveCommands
                .set(lockKey, &#34;PROCESSING&#34;, setArgs)
                .switchIfEmpty(Mono.defer(() -&gt; {
                    System.out.println(&#34;lock not acquired, doing nothing&#34;);
                    return Mono.empty();
                }))
                .flatMap(acquired -&gt; {
                    if (acquired.equals(&#34;OK&#34;)) {
                        System.out.println(&#34;lock acquired, returning mono&#34;);
                        return thingToDo
                                .onErrorResume(throwable -&gt;
                                        redisReactiveCommands
                                                .del(lockKey)
                                                .then(Mono.error(throwable))
                                )
                                .then(redisReactiveCommands.set(lockKey, &#34;PROCESSED&#34;, new SetArgs().ex(200)).then());
                    }

                    // we can further improve this situation by signaling whether we&#39;re PROCESSING or PROCESSED to the caller
                    return Mono.error(new RuntimeException(&#34;whoops!&#34;));
                });
    }

```

This improves the situation for us and addresses some of the edge cases we need to worry about. I can write a test that uses this helper method with something like:

```java
    @Test
    public void distributedLockingAndErrorHandling() {
        AtomicInteger numTimesCalled = new AtomicInteger(0);
        Mono&lt;Void&gt; errorMono = Mono.defer(() -&gt; {
            System.out.println(&#34;returning an error&#34;);
            numTimesCalled.incrementAndGet();
            return Mono.error(new RuntimeException(&#34;ahhhh&#34;));
        });

        Mono&lt;Void&gt; successMono = Mono.defer(() -&gt; {
            System.out.println(&#34;returning success&#34;);
            numTimesCalled.incrementAndGet();
            return Mono.empty();
        });

        StepVerifier.create(doIfLockAcquiredAndHandleErrors(&#34;lock-123&#34;, errorMono))
                .verifyError();

        StepVerifier.create(doIfLockAcquiredAndHandleErrors(&#34;lock-123&#34;, errorMono))
                .verifyError();

        StepVerifier.create(doIfLockAcquiredAndHandleErrors(&#34;lock-123&#34;, errorMono))
                .verifyError();

        StepVerifier.create(doIfLockAcquiredAndHandleErrors(&#34;lock-123&#34;, successMono))
                .verifyComplete();

        // errors should cause the lock to be released
        assertEquals(4, numTimesCalled.get());

        // we should have finally succeeded, which means the lock is marked as processed
        StepVerifier.create(redisReactiveCommands.get(&#34;lock-123&#34;))
                .expectNext(&#34;PROCESSED&#34;)
                .verifyComplete();
    }

```

Here, if we use the same lock on a **Mono** that is erroring out on us, we eventually succeed because our locking helper method is deleting the lock after the operation failed for us.

Finally, I have arbitrarily chosen 20 seconds and 200 seconds as the timeout for the PROCESSING and PROCESSED lock states, you will want to be sure to tune this to be relevant for your application.
