---
title: "How to use Caffeine Caches Effectively in Spring Boot Webflux"
date: 2021-03-13T21:36:45
draft: false
tags: [maven, reactive, webflux]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/api-calls-and-resilience).

When someone talks about a caffeine cache, they are talking about [Ben Manes caching library](https://github.com/ben-manes/caffeine), which is a high performance, in memory cache written for java. If you're using reactive streams, you can't reliably use a LoadingCache because it's blocking by default. Thankfully, tapping into a couple of basic features of reactive streams and caffeine can get us there.

I'm going to build off of some sample code in a previous blog post about a more primitive form of [caching in webflux](https://nickolasfisher.com/blog/InMemory-Caching-in-Sprint-Boot-WebfluxProject-Reactor), if you recall we had a **RetryService** that made a downstream network call like so:

```java
@Service
public class RetryService {
    private final WebClient serviceAWebClient;

    public RetryService(@Qualifier("service-a-web-client") WebClient serviceAWebClient) {
        this.serviceAWebClient = serviceAWebClient;
    }

    public Mono<WelcomeMessage> getWelcomeMessageAndHandleTimeout(String locale) {
        return this.serviceAWebClient.get()
                .uri(uriBuilder -> uriBuilder.path("/locale/{locale}/message").build(locale))
                .retrieve()
                .bodyToMono(WelcomeMessage.class)
                .retryWhen(
                    Retry.backoff(2, Duration.ofMillis(25))
                            .filter(throwable -> throwable instanceof TimeoutException)
                );
    }
}

```

What the service does isn't particularly important for this article, however--let's just say we have business logic that allows us to cache this for brief periods of time upstream. This logic very rarely changes, and the dataset is small. Therefore, it is an excellent candidate for in memory caching to improve performance.

The first thing we'll do is make a **CachingService** that wraps our **RetryService**, and a skeleton method that we'll fill in in a moment:

```java
@Service
public class CachingService {

    private final RetryService retryService;

    public CachingService(RetryService retryService) {
        this.retryService = retryService;
    }

    public Mono<WelcomeMessage> getCachedWelcomeMono(String locale) {
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

Now we'll write a unit test targeting the behavior we want to see: what we want is that successive calls with the same locale gets us the same response, and we don't continue to invoke the underlying service that actually produces that value in that case. We can also sanity check that different locale inputs get different outputs:

```java
    @Test
    public void getCachedWelcomeMono_cachesSuccess() {
        RetryService mockRetryService = Mockito.mock(RetryService.class);

        AtomicInteger timesInvoked = new AtomicInteger(0);
        Mockito.when(mockRetryService.getWelcomeMessageAndHandleTimeout(anyString()))
                .thenAnswer(new Answer<Mono<WelcomeMessage>>() {
                    @Override
                    public Mono<WelcomeMessage> answer(InvocationOnMock invocation) throws Throwable {
                        String locale_arg = invocation.getArgument(0);
                        return Mono.defer(() -> {
                            timesInvoked.incrementAndGet();
                            return Mono.just(new WelcomeMessage("locale " + locale_arg));
                        });
                    }
                });

        CachingService cachingService = new CachingService(mockRetryService);

        for (int i = 0; i < 3; i++) {
            StepVerifier.create(cachingService.getCachedWelcomeMono("en"))
                    .expectNextMatches(welcomeMessage -> "locale en".equals(welcomeMessage.getMessage()))
                    .verifyComplete();
        }

        for (int i = 0; i < 5; i++) {
            StepVerifier.create(cachingService.getCachedWelcomeMono("ru"))
                    .expectNextMatches(welcomeMessage -> "locale ru".equals(welcomeMessage.getMessage()))
                    .verifyComplete();
        }

        assertEquals(2, timesInvoked.get());
    }

```

Here, we setup a mock response that uses the argument to generate the response, leveraging Mockito, and then we make 3 requests to this caching service in succession for the english locale. We follow up with five requests for the russian locale. If you run this test now, it will fail, because we assert that the underlying mono from the mock service was invoked only twice--which will be true when we add caching but is currently false. We can get this test to pass with the following code:

```java
        private final Cache<String, WelcomeMessage>
            WELCOME_MESSAGE_CACHE = Caffeine.newBuilder()
                                        .expireAfterWrite(Duration.ofMinutes(5))
                                        .maximumSize(1_000)
                                        .build();

    public Mono<WelcomeMessage> getCachedWelcomeMono(String locale) {
        Optional<WelcomeMessage> message = Optional.ofNullable(WELCOME_MESSAGE_CACHE.getIfPresent(locale));

        return message
                .map(Mono::just)
                .orElseGet(() ->
                        this.retryService.getWelcomeMessageAndHandleTimeout(locale)
                            .doOnNext(welcomeMessage -> WELCOME_MESSAGE_CACHE.put(locale, welcomeMessage))
                );
    }

```

Here, we check if the message is in the cache \[returning it if it is\]. If it does not exist, we request it from the underlying service and, once the underlying service responds successfully, we manually populate the cache ourselves with a **doOnNext**.

It's important, though not particularly consequential, to note that this means that in very high throughput services, this will result in multiple calls to the downstream service because this is a check-then-act process that does not lock. But that should be perfectly fine for the vast majority of cases.

Remember to check out the [source code for this post on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/api-calls-and-resilience). Happy caching.
