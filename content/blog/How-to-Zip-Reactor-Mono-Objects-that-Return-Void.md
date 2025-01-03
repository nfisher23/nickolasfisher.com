---
title: "How to Zip Reactor Mono Objects that Return Void"
date: 2021-03-20T19:14:57
draft: false
tags: [java, concurrency, reactive, webflux]
---

Leveraging [Mono.zip](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#zip-java.lang.Iterable-java.util.function.Function-) appropriately will \[with the right configuration\] lead to a high amount of performance and concurrency. There is one caveat to its usage though:

> An error or **empty** completion of any source will cause other sources
> to be cancelled and the resulting Mono to immediately error or complete, respectively.

This ultimately means we need to make sure that every **Mono** that we plug into a zip needs to emit a value \[ **onNext**\]. Returning an empty **Mono** will cause us pain and suffering, as this failing unit test should demonstrate:

```java
    @Test
    public void handleVoidsInMonos() {
        Mono<Void> monoThatDoesSomething = Mono.defer(() -> Mono.empty());
        Object objectReturned = new Object();
        Mono<Object> monoThatReturnsSomething = Mono.defer(() -> {
            return Mono.just(objectReturned);
        });

        List<Mono<?>> monoCollection = Arrays.asList(monoThatReturnsSomething, monoThatDoesSomething);

        StepVerifier.create(Mono.zip(monoCollection, objects -> objects[0]))
                // fails
                .expectNextMatches(obj -> obj == objectReturned)
                .verifyComplete();
    }

```

Here, we fail on **expectNextMatches**, because the **monoThatDoesSomething** completes without emitting an item.

This can be a problem if you have a mismash of **Mono**
objects that you want to zip up and execute concurrently. There is only
one safe way I currently know how to deal with this, which is to extend
the **Mono**\[s\] that are designed to return **Void** or empty to have a default:

```java

    @Test
    public void handleVoidsInMonos_works() {
        Mono<Void> monoThatDoesSomething = Mono.defer(() -> Mono.empty());
        Object objectReturned = new Object();

        Mono<Object> monoThatReturnsSomething = Mono.defer(() -> Mono.just(objectReturned));

        List<Mono<?>> monoCollection = Arrays.asList(
                monoThatReturnsSomething,
                monoThatDoesSomething.then(Mono.just(new Object()))
            );

        Mono<Object> zipped = Mono.zip(monoCollection, objects -> objects[0]);
        StepVerifier.create(zipped)
                .expectNextMatches(obj -> obj == objectReturned)
                .verifyComplete();
    }

```

This test passes because we're saying "once **monoThatDoesSomething** completes, immediately return a **Mono** that has just an empty object in it. We then submit that **Mono** to the zip rather than the original that didn't emit an item.

If you stare hard at the quote in the method definition, then you'll understand that this is a safe way to ensure all of the **Mono**\[s\] submitted to the zip complete correctly, and any other method to do this will also need to keep that quote in mind.
