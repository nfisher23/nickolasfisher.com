---
title: "Making Sense of Mono Error Handling in Spring Boot Webflux/Project Reactor"
date: 2021-03-21T18:27:16
draft: false
tags: [java, spring, reactive, webflux]
---

A Reactor [Mono](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html) comes with a lot of methods that allow you to do things when errors occur:

- [onErrorContinue](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorContinue-java.util.function.BiConsumer-)
- [onErrorMap](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorMap-java.lang.Class-java.util.function.Function-)
- [onErrorResume](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorResume-java.lang.Class-java.util.function.Function-)
- [onErrorReturn](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorReturn-java.lang.Class-T-)

How many of these are actually valuable? In practice, the only one you're likely to care about using is **onErrorResume**. The rest aren't super valuable. I'm going to run through these in order of increasing usefulness.

### onErrorResume

This one you will use probably 95% of the time. It's simple: if the mono upstream emits an error, you get to decide how to deal with it. Here's an example:

```java
    @Test
    public void onErrorMono_simple() {
        Mono<Object> errorMono = Mono.defer(() ->
            Mono.error(new IllegalArgumentException("wat"))
        );

        StepVerifier.create(errorMono
            .onErrorResume(new Function<Throwable, Mono<?>>() {
                @Override
                public Mono<?> apply(Throwable throwable) {
                    return Mono.just("fallback");
                }
            }))
            .expectNextMatches(obj -> "fallback".equals(obj))
            .verifyComplete();
    }

```

Here, we just blindly provide a static fallback. If at any time the **errorMono** returns an error, we always fallback to a string with value "fallback".

In the case where you have a fallback option that isn't static--for example, you're trying to contact the primary database and it fails, so you fallback to a cache, you can do pretty much the same thing, and just fallback to a **Mono** that actually does something \[typically in the form of a service\]:

```java
    @Test
    public void onErrorMono_slightlyLessSimple() {
        Mono<Object> errorMono = Mono.defer(() ->
                Mono.error(new IllegalArgumentException("wat"))
        );

        Mono<Object> fallbackMono = Mono.defer(() ->
                // in real life, for example, fallback to something like a cache, which
                // may or may not be another network call
                Mono.just("fallback")
        );

        StepVerifier.create(errorMono
                .onErrorResume(new Function<Throwable, Mono<?>>() {
                    @Override
                    public Mono<?> apply(Throwable throwable) {
                        return fallbackMono;
                    }
                }))
                .expectNextMatches(obj -> "fallback".equals(obj))
                .verifyComplete();
    }

```

If **fallbackMono** fails, in this case, then the entire chain will fail as the error termination signal will be propagated downstream. If that actually makes another call, you'll probably want to have a fallback for that fallback.

There's another variant here that's worth mentioning. You can introduce a [Predicate](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/function/Predicate.html) to match against an exception, then you'll only conditionally execute the fallback behavior. This is very valuable when you're dealing with downstream service calls, for example, because you probably want to match on a **5xx** response code, but matching on a **4xx** response code would be irresponsible \[client side error, after all\]. So you can chain **onErrorResume** calls until you get the match you want, and tune your fallback appropriately:

```java
    @Test
    public void onErrorMono_matching() {
        Mono<Object> errorMono = Mono.defer(() ->
                Mono.error(new IllegalArgumentException("real illegal arg"))
        );

        Mono<Object> fallbackMono = Mono.defer(() ->
                // in real life, for example, fallback to something like a cache, which
                // may or may not be another network call
                Mono.just("fallback")
        );

        StepVerifier.create(errorMono
                .onErrorResume(
                    exception -> exception.getMessage().equals("wat"),
                    throwable -> fallbackMono
                ).onErrorResume(
                    exception -> exception.getMessage().equals("real illegal arg"),
                    throwable -> Mono.just("second fallback")
                )
            )
            .expectNextMatches(obj -> "second fallback".equals(obj))
            .verifyComplete();
    }

```

Here we have two different types of fallback behaviors depending on the message inside the exception itself. Only the second one matches, which is why this test passes.

### onErrorReturn

This one is basically a simplified version of **onErrorResume**. You can provide a static value to fall back to:

```java
    @Test
    public void onErrorMono_returnStatic() {
        Mono<Object> errorMono = Mono.defer(() ->
                Mono.error(new IllegalArgumentException("wat"))
        );

        StepVerifier.create(errorMono.onErrorReturn("fallback"))
                .expectNextMatches(obj -> "fallback".equals(obj))
                .verifyComplete();
    }

```

There are similar variants that correspond to **onErrorResume** behavior, outlined above.

In practice, what's the added value here? An ever so slight amount of reduced verbosity, as you don't have to wrap the returned value with a **Mono.just**. That's it.

### onErrorMap

This one is just used to map one error type to another:

```java
    @Test
    public void onErrorMono_map() {
        Mono<Object> errorMono = Mono.defer(() ->
            Mono.error(new IllegalArgumentException("wat"))
        );

        StepVerifier.create(errorMono.onErrorMap(new Function<Throwable, Throwable>() {
                    @Override
                    public Throwable apply(Throwable throwable) {
                        return new NullPointerException("different exception");
                    }
                }))
                .expectError(NullPointerException.class).verify();
    }

```

In practice you're not likely to use this much, unless you want to change some underlying service behavior to abstract/adapt exceptions that the underlying library is emitting \[e.g. WebClient\]

### onErrorContinue

To quote the documentation for this class of methods:

**"The mode doesn't really make sense on a Mono, since we're sure there will be no further value to continue with: onErrorResume(Function) is a more classical fit then."**

It's only really useful if you're propagating the configuration to an upstream **Flux**. I wouldn't suggest spending a lot of time on this one and stick to **onErrorResume**.
