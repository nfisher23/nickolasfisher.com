---
title: "Making Sense of Mono Error Handling in Spring Boot Webflux/Project Reactor"
date: 2021-03-01T00:00:00
draft: false
---

A Reactor [Mono](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html) comes with a lot of methods that allow you to do things when errors occur:

- [onErrorContinue](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorContinue-java.util.function.BiConsumer-)
- [onErrorMap](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorMap-java.lang.Class-java.util.function.Function-)
- [onErrorResume](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorResume-java.lang.Class-java.util.function.Function-)
- [onErrorReturn](https://projectreactor.io/docs/core/release/api/reactor/core/publisher/Mono.html#onErrorReturn-java.lang.Class-T-)

How many of these are actually valuable? In practice, the only one you&#39;re likely to care about using is **onErrorResume**. The rest aren&#39;t super valuable. I&#39;m going to run through these in order of increasing usefulness.

### onErrorResume

This one you will use probably 95% of the time. It&#39;s simple: if the mono upstream emits an error, you get to decide how to deal with it. Here&#39;s an example:

``` java
    @Test
    public void onErrorMono_simple() {
        Mono&lt;Object&gt; errorMono = Mono.defer(() -&gt;
            Mono.error(new IllegalArgumentException(&#34;wat&#34;))
        );

        StepVerifier.create(errorMono
            .onErrorResume(new Function&lt;Throwable, Mono&lt;?&gt;&gt;() {
                @Override
                public Mono&lt;?&gt; apply(Throwable throwable) {
                    return Mono.just(&#34;fallback&#34;);
                }
            }))
            .expectNextMatches(obj -&gt; &#34;fallback&#34;.equals(obj))
            .verifyComplete();
    }

```

Here, we just blindly provide a static fallback. If at any time the **errorMono** returns an error, we always fallback to a string with value &#34;fallback&#34;.

In the case where you have a fallback option that isn&#39;t static--for example, you&#39;re trying to contact the primary database and it fails, so you fallback to a cache, you can do pretty much the same thing, and just fallback to a **Mono** that actually does something \[typically in the form of a service\]:

``` java
    @Test
    public void onErrorMono_slightlyLessSimple() {
        Mono&lt;Object&gt; errorMono = Mono.defer(() -&gt;
                Mono.error(new IllegalArgumentException(&#34;wat&#34;))
        );

        Mono&lt;Object&gt; fallbackMono = Mono.defer(() -&gt;
                // in real life, for example, fallback to something like a cache, which
                // may or may not be another network call
                Mono.just(&#34;fallback&#34;)
        );

        StepVerifier.create(errorMono
                .onErrorResume(new Function&lt;Throwable, Mono&lt;?&gt;&gt;() {
                    @Override
                    public Mono&lt;?&gt; apply(Throwable throwable) {
                        return fallbackMono;
                    }
                }))
                .expectNextMatches(obj -&gt; &#34;fallback&#34;.equals(obj))
                .verifyComplete();
    }

```

If **fallbackMono** fails, in this case, then the entire chain will fail as the error termination signal will be propagated downstream. If that actually makes another call, you&#39;ll probably want to have a fallback for that fallback.

There&#39;s another variant here that&#39;s worth mentioning. You can introduce a [Predicate](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/function/Predicate.html) to match against an exception, then you&#39;ll only conditionally execute the fallback behavior. This is very valuable when you&#39;re dealing with downstream service calls, for example, because you probably want to match on a **5xx** response code, but matching on a **4xx** response code would be irresponsible \[client side error, after all\]. So you can chain **onErrorResume** calls until you get the match you want, and tune your fallback appropriately:

``` java
    @Test
    public void onErrorMono_matching() {
        Mono&lt;Object&gt; errorMono = Mono.defer(() -&gt;
                Mono.error(new IllegalArgumentException(&#34;real illegal arg&#34;))
        );

        Mono&lt;Object&gt; fallbackMono = Mono.defer(() -&gt;
                // in real life, for example, fallback to something like a cache, which
                // may or may not be another network call
                Mono.just(&#34;fallback&#34;)
        );

        StepVerifier.create(errorMono
                .onErrorResume(
                    exception -&gt; exception.getMessage().equals(&#34;wat&#34;),
                    throwable -&gt; fallbackMono
                ).onErrorResume(
                    exception -&gt; exception.getMessage().equals(&#34;real illegal arg&#34;),
                    throwable -&gt; Mono.just(&#34;second fallback&#34;)
                )
            )
            .expectNextMatches(obj -&gt; &#34;second fallback&#34;.equals(obj))
            .verifyComplete();
    }

```

Here we have two different types of fallback behaviors depending on the message inside the exception itself. Only the second one matches, which is why this test passes.

### onErrorReturn

This one is basically a simplified version of **onErrorResume**. You can provide a static value to fall back to:

``` java
    @Test
    public void onErrorMono_returnStatic() {
        Mono&lt;Object&gt; errorMono = Mono.defer(() -&gt;
                Mono.error(new IllegalArgumentException(&#34;wat&#34;))
        );

        StepVerifier.create(errorMono.onErrorReturn(&#34;fallback&#34;))
                .expectNextMatches(obj -&gt; &#34;fallback&#34;.equals(obj))
                .verifyComplete();
    }

```

There are similar variants that correspond to **onErrorResume** behavior, outlined above.

In practice, what&#39;s the added value here? An ever so slight amount of reduced verbosity, as you don&#39;t have to wrap the returned value with a **Mono.just**. That&#39;s it.

### onErrorMap

This one is just used to map one error type to another:

``` java
    @Test
    public void onErrorMono_map() {
        Mono&lt;Object&gt; errorMono = Mono.defer(() -&gt;
            Mono.error(new IllegalArgumentException(&#34;wat&#34;))
        );

        StepVerifier.create(errorMono.onErrorMap(new Function&lt;Throwable, Throwable&gt;() {
                    @Override
                    public Throwable apply(Throwable throwable) {
                        return new NullPointerException(&#34;different exception&#34;);
                    }
                }))
                .expectError(NullPointerException.class).verify();
    }

```

In practice you&#39;re not likely to use this much, unless you want to change some underlying service behavior to abstract/adapt exceptions that the underlying library is emitting \[e.g. WebClient\]

### onErrorContinue

To quote the documentation for this class of methods:

**&#34;The mode doesn&#39;t really make sense on a Mono, since we&#39;re sure there will be no further value to continue with: onErrorResume(Function) is a more classical fit then.&#34;**

It&#39;s only really useful if you&#39;re propagating the configuration to an upstream **Flux**. I wouldn&#39;t suggest spending a lot of time on this one and stick to **onErrorResume**.


