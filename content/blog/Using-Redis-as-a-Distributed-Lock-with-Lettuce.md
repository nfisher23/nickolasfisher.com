---
title: "Using Redis as a Distributed Lock with Lettuce"
date: 2021-05-01T14:44:31
draft: false
tags: [java, distributed systems, reactive, webflux, lettuce, redis]
---

The source code for this article [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Using Redis as a best effort locking mechanism can be very useful in practice, to prevent two logical threads from clobbering each other. While redis locking is certainly not perfect, and [you shouldn't use redis locking if the underlying operation can't be occasionally done twice](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html), it can still be useful for that "best effort, do this once" use case.

### Basic Order of Operations

The non edge case scenario can look like:

1. Atomically acquire a lock with a timeout
2. Get a boolean response: Lock acquired/Lock not acquired
3. If lock acquired, do your work
4. If lock not acquired, do nothing

There are some key edge cases we'll want to pay attention to, but this is the gist of it.

### Naive Implementation

Note: it will be much easier to follow along if you know [how to configure embedded redis to test a reactive lettuce client](https://nickolasfisher.com/blog/how-to-use-embedded-redis-to-test-a-lettuce-client-in-spring-boot-webflux) or [how to configure a test container to test a redis client](https://nickolasfisher.com/blog/how-to-use-a-redis-test-container-with-lettucespring-boot-webflux).

A simple implementation of our problem can look like this:

```java
    public Mono<Void> simpleDoIfLockAcquired(String lockKey, Mono<Void> thingToDo) {
        return redisReactiveCommands.setnx(lockKey, "ACQUIRED")
                .flatMap(acquired -> {
                    if (acquired) {
                        System.out.println("lock acquired, returning mono");
                        return thingToDo;
                    } else {
                        System.out.println("lock not acquired, doing nothing");
                        return Mono.empty();
                    }
                });
    }

```

Here, we're using SETNX to atomically write a key with a value to redis. If the write fails, SETNX will tell us that is failed. We can pass in any operation \[represented as a Mono\] that we want to be performed. Here's an example using it and verifying we don't do anything twice in the normal use case:

```java
    @Test
    public void distributedLocking() {
        AtomicInteger numTimesCalled = new AtomicInteger(0);
        Mono<Void> justLogItMono = Mono.defer(() -> {
            System.out.println("not doing anything, just logging");
            numTimesCalled.incrementAndGet();
            return Mono.empty();
        });

        StepVerifier.create(simpleDoIfLockAcquired("lock-123", justLogItMono))
                .verifyComplete();

        StepVerifier.create(simpleDoIfLockAcquired("lock-123", justLogItMono))
                .verifyComplete();

        StepVerifier.create(simpleDoIfLockAcquired("lock-123", justLogItMono))
                .verifyComplete();

        assertEquals(1, numTimesCalled.get());
    }

```

This test counts the number of times our **justLogItMono** actually gets invoked, and because we use the same locking key every time, it only gets invoked once.

### Handling Edge Cases

We have a couple of problems with the above implementation, however.

For one, we have no timeout on that lock--so if the underlying thing that we're doing fails unexpectedly, it never gets done. For two, we have no way of saying whether we're currently processing the underlying operation or whether we have already finished it, or processed it \[which is useful if another thread comes along later, because then that thread knows to abandon the operation completely rather than wait until the lease expires\]. Finally, if there are any errors when doing the underlying operation, ideally we would just release the lock right away so another thread could retry when the time comes.

We can improve upon this situation with some code like the following:

```java
    public Mono<Void> doIfLockAcquiredAndHandleErrors(String lockKey, Mono<Void> thingToDo) {
        SetArgs setArgs = new SetArgs().nx().ex(20);
        return redisReactiveCommands
                .set(lockKey, "PROCESSING", setArgs)
                .switchIfEmpty(Mono.defer(() -> {
                    System.out.println("lock not acquired, doing nothing");
                    return Mono.empty();
                }))
                .flatMap(acquired -> {
                    if (acquired.equals("OK")) {
                        System.out.println("lock acquired, returning mono");
                        return thingToDo
                                .onErrorResume(throwable ->
                                        redisReactiveCommands
                                                .del(lockKey)
                                                .then(Mono.error(throwable))
                                )
                                .then(redisReactiveCommands.set(lockKey, "PROCESSED", new SetArgs().ex(200)).then());
                    }

                    // we can further improve this situation by signaling whether we're PROCESSING or PROCESSED to the caller
                    return Mono.error(new RuntimeException("whoops!"));
                });
    }

```

This improves the situation for us and addresses some of the edge cases we need to worry about. I can write a test that uses this helper method with something like:

```java
    @Test
    public void distributedLockingAndErrorHandling() {
        AtomicInteger numTimesCalled = new AtomicInteger(0);
        Mono<Void> errorMono = Mono.defer(() -> {
            System.out.println("returning an error");
            numTimesCalled.incrementAndGet();
            return Mono.error(new RuntimeException("ahhhh"));
        });

        Mono<Void> successMono = Mono.defer(() -> {
            System.out.println("returning success");
            numTimesCalled.incrementAndGet();
            return Mono.empty();
        });

        StepVerifier.create(doIfLockAcquiredAndHandleErrors("lock-123", errorMono))
                .verifyError();

        StepVerifier.create(doIfLockAcquiredAndHandleErrors("lock-123", errorMono))
                .verifyError();

        StepVerifier.create(doIfLockAcquiredAndHandleErrors("lock-123", errorMono))
                .verifyError();

        StepVerifier.create(doIfLockAcquiredAndHandleErrors("lock-123", successMono))
                .verifyComplete();

        // errors should cause the lock to be released
        assertEquals(4, numTimesCalled.get());

        // we should have finally succeeded, which means the lock is marked as processed
        StepVerifier.create(redisReactiveCommands.get("lock-123"))
                .expectNext("PROCESSED")
                .verifyComplete();
    }

```

Here, if we use the same lock on a **Mono** that is erroring out on us, we eventually succeed because our locking helper method is deleting the lock after the operation failed for us.

Finally, I have arbitrarily chosen 20 seconds and 200 seconds as the timeout for the PROCESSING and PROCESSED lock states, you will want to be sure to tune this to be relevant for your application.
