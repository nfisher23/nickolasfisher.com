---
title: "How to Unit Test that a Reactor Mono was Actually Subscribed to"
date: 2021-03-13T22:35:48
draft: false
---

There&#39;s a very insidious bug that can happen when you&#39;re writing reactive code, and it basically comes down to whether an underlying **Mono** in a chain of operations was actually **subscribed to**, rather than merely observing a method invocation. I&#39;ll demonstrate with an example.

Let&#39;s say you&#39;re writing a service that gets a piece of information, then sends that piece of information off to a downstream service for processing. Maybe you just want to record an event in some kind of crude event service, or write to that event database. In that situation, you effectively just want to ensure you successfully sent that piece of information and receive an acknowledgment of a response.

So you go ahead and write a test that looks something like this:

```java
    @Test
    public void nothing() {
        RetryService mockRetryService = Mockito.mock(RetryService.class);

        Mockito.when(mockRetryService.doAThing(anyString()))
                .thenReturn(Mono.empty());
        Mockito.when(mockRetryService.getSomething(anyString()))
                .thenReturn(Mono.just(new WelcomeMessage(&#34;k&#34;)));

        CachingService cachingService = new CachingService(mockRetryService);

        StepVerifier.create(cachingService.getThenAct())
                .verifyComplete();

        Mockito.verify(mockRetryService).doAThing(&#34;k&#34;); // &lt;-- this is not testing what you think
    }

```

As displayed in the comment, this code is not verifying that the underlying Mono that was returned was actually _subscribed to_. All you&#39;re verifying here is that the method **doAThing** was invoked. Because nothing happens until you **subscribe**, the effect your looking for is not guaranteed to happen with this test.

Here&#39;s an example where I pass this unit test, but the actual operation that **doAThing** is supposed to do when invoked does not happen:

```java
    public Mono&lt;Void&gt; getThenAct() {
        return this.retryService.getSomething(&#34;something&#34;)
                // bug!
                .map(messageDTO -&gt; retryService.doAThing(messageDTO.getMessage()))
                .then();
    }

```

To fix this problem, we want to track the subscription, not just the method invocation. Here&#39;s an example where we can fix our test to do that:

```java
    @Test
    public void nothing() {
        RetryService mockRetryService = Mockito.mock(RetryService.class);

        AtomicInteger timesInvoked = new AtomicInteger(0);
        Mockito.when(mockRetryService.doAThing(anyString()))
                .thenReturn(Mono.defer(() -&gt; {
                    timesInvoked.incrementAndGet();
                    return Mono.empty();
                }));

        Mockito.when(mockRetryService.getSomething(anyString()))
                .thenReturn(Mono.just(new WelcomeMessage(&#34;k&#34;)));

        CachingService cachingService = new CachingService(mockRetryService);

        StepVerifier.create(cachingService.getThenAct())
                .verifyComplete();

        Mockito.verify(mockRetryService).doAThing(&#34;k&#34;);
        assertEquals(1, timesInvoked.get());
    }

```

Here, we use an **AtomicInteger** just to get around the inability of java programs to modify captured variables \[they have to be final/effectively final\], but the effect is the same: we&#39;re counting the number of times the **Mono** that we return is actually subscribed to, rather than just verifying method signature. Then at the end of the test we assert that it was subscribed to one time.

If you run this test as it stands, it will fail. We can now write code to get that test to pass:

```java
    public Mono&lt;Void&gt; getThenAct() {
        return this.retryService.getSomething(&#34;something&#34;)
                // not a bug!
                .flatMap(messageDTO -&gt; retryService.doAThing(messageDTO.getMessage()))
                .then();
    }

```

In reactive programming, write unit tests that verify that **Mono**&#39;s are actually subscribed to in this way if they return a **Void**, or you will regret it at some point, in the form of a bug.
