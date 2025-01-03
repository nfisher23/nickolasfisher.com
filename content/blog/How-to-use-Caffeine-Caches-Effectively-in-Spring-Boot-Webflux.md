---
title: "How to use Caffeine Caches Effectively in Spring Boot Webflux"
date: 2021-03-13T21:36:45
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/api-calls-and-resilience).

When someone talks about a caffeine cache, they are talking about [Ben Manes caching library](https://github.com/ben-manes/caffeine), which is a high performance, in memory cache written for java. If you&#39;re using reactive streams, you can&#39;t reliably use a LoadingCache because it&#39;s blocking by default. Thankfully, tapping into a couple of basic features of reactive streams and caffeine can get us there.

I&#39;m going to build off of some sample code in a previous blog post about a more primitive form of [caching in webflux](https://nickolasfisher.com/blog/InMemory-Caching-in-Sprint-Boot-WebfluxProject-Reactor), if you recall we had a **RetryService** that made a downstream network call like so:

```java
@Service
public class RetryService {
    private final WebClient serviceAWebClient;

    public RetryService(@Qualifier(&#34;service-a-web-client&#34;) WebClient serviceAWebClient) {
        this.serviceAWebClient = serviceAWebClient;
    }

    public Mono&lt;WelcomeMessage&gt; getWelcomeMessageAndHandleTimeout(String locale) {
        return this.serviceAWebClient.get()
                .uri(uriBuilder -&gt; uriBuilder.path(&#34;/locale/{locale}/message&#34;).build(locale))
                .retrieve()
                .bodyToMono(WelcomeMessage.class)
                .retryWhen(
                    Retry.backoff(2, Duration.ofMillis(25))
                            .filter(throwable -&gt; throwable instanceof TimeoutException)
                );
    }
}

```

What the service does isn&#39;t particularly important for this article, however--let&#39;s just say we have business logic that allows us to cache this for brief periods of time upstream. This logic very rarely changes, and the dataset is small. Therefore, it is an excellent candidate for in memory caching to improve performance.

The first thing we&#39;ll do is make a **CachingService** that wraps our **RetryService**, and a skeleton method that we&#39;ll fill in in a moment:

```java
@Service
public class CachingService {

    private final RetryService retryService;

    public CachingService(RetryService retryService) {
        this.retryService = retryService;
    }

    public Mono&lt;WelcomeMessage&gt; getCachedWelcomeMono(String locale) {
        return Mono.empty();
    }
}

```

This is where **WelcomeMessage** is a simple DTO like so:

```java
public class WelcomeMessage {
    private String message;

    public WelcomeMessage() {}

    public WelcomeMessage(String message) {
        this.message = message;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }
}

```

Now we&#39;ll write a unit test targeting the behavior we want to see: what we want is that successive calls with the same locale gets us the same response, and we don&#39;t continue to invoke the underlying service that actually produces that value in that case. We can also sanity check that different locale inputs get different outputs:

```java
    @Test
    public void getCachedWelcomeMono_cachesSuccess() {
        RetryService mockRetryService = Mockito.mock(RetryService.class);

        AtomicInteger timesInvoked = new AtomicInteger(0);
        Mockito.when(mockRetryService.getWelcomeMessageAndHandleTimeout(anyString()))
                .thenAnswer(new Answer&lt;Mono&lt;WelcomeMessage&gt;&gt;() {
                    @Override
                    public Mono&lt;WelcomeMessage&gt; answer(InvocationOnMock invocation) throws Throwable {
                        String locale_arg = invocation.getArgument(0);
                        return Mono.defer(() -&gt; {
                            timesInvoked.incrementAndGet();
                            return Mono.just(new WelcomeMessage(&#34;locale &#34; &#43; locale_arg));
                        });
                    }
                });

        CachingService cachingService = new CachingService(mockRetryService);

        for (int i = 0; i &lt; 3; i&#43;&#43;) {
            StepVerifier.create(cachingService.getCachedWelcomeMono(&#34;en&#34;))
                    .expectNextMatches(welcomeMessage -&gt; &#34;locale en&#34;.equals(welcomeMessage.getMessage()))
                    .verifyComplete();
        }

        for (int i = 0; i &lt; 5; i&#43;&#43;) {
            StepVerifier.create(cachingService.getCachedWelcomeMono(&#34;ru&#34;))
                    .expectNextMatches(welcomeMessage -&gt; &#34;locale ru&#34;.equals(welcomeMessage.getMessage()))
                    .verifyComplete();
        }

        assertEquals(2, timesInvoked.get());
    }

```

Here, we setup a mock response that uses the argument to generate the response, leveraging Mockito, and then we make 3 requests to this caching service in succession for the english locale. We follow up with five requests for the russian locale. If you run this test now, it will fail, because we assert that the underlying mono from the mock service was invoked only twice--which will be true when we add caching but is currently false. We can get this test to pass with the following code:

```java
        private final Cache&lt;String, WelcomeMessage&gt;
            WELCOME_MESSAGE_CACHE = Caffeine.newBuilder()
                                        .expireAfterWrite(Duration.ofMinutes(5))
                                        .maximumSize(1_000)
                                        .build();

    public Mono&lt;WelcomeMessage&gt; getCachedWelcomeMono(String locale) {
        Optional&lt;WelcomeMessage&gt; message = Optional.ofNullable(WELCOME_MESSAGE_CACHE.getIfPresent(locale));

        return message
                .map(Mono::just)
                .orElseGet(() -&gt;
                        this.retryService.getWelcomeMessageAndHandleTimeout(locale)
                            .doOnNext(welcomeMessage -&gt; WELCOME_MESSAGE_CACHE.put(locale, welcomeMessage))
                );
    }

```

Here, we check if the message is in the cache \[returning it if it is\]. If it does not exist, we request it from the underlying service and, once the underlying service responds successfully, we manually populate the cache ourselves with a **doOnNext**.

It&#39;s important, though not particularly consequential, to note that this means that in very high throughput services, this will result in multiple calls to the downstream service because this is a check-then-act process that does not lock. But that should be perfectly fine for the vast majority of cases.

Remember to check out the [source code for this post on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/api-calls-and-resilience). Happy caching.
