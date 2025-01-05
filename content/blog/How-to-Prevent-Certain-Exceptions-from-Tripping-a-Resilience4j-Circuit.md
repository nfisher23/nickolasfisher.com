---
title: "How to Prevent Certain Exceptions from Tripping a Resilience4j Circuit"
date: 2021-05-01T21:14:55
draft: false
tags: [java, resilience]
---

The source code for this article [can be found on Github](https://github.com/nfisher23/java-failure-and-resilience).

The Resilience4j circuit breaker by default considers any exception thrown inside of the **Supplier** as a failure. If over 50% of the calls are failures and the rolling window max size is met, then it will prevent any future calls from going through.

It's not uncommon to throw exceptions as a part of normal business logic--they might be thrown because of an _exceptional circumstance_, but that doesn't mean that there is an error or something wrong with the downstream resource you're trying to interact with. For example, Spring's **RestTemplate** will throw an exception on a 4xx response code, and this will by default trip the circuit and prevent future calls from going through:

```java
    @Test
    public void clientErrorException_stillTripsTheCircuit() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath("/some/endpoint/10");

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(404));

        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .slidingWindowSize(10)
                .build();

        CircuitBreakerRegistry circuitBreakerRegistry =
                CircuitBreakerRegistry.of(circuitBreakerConfig);

        CircuitBreaker callingEndpointCircuitBreaker = circuitBreakerRegistry.circuitBreaker("call-endpoint");

        // force the circuit to trip
        for (int i = 1; i < 11; i++) {
            try {
                callingEndpointCircuitBreaker.decorateSupplier(() ->
                        restTemplate.getForEntity("/some/endpoint/10", JsonNode.class)
                ).get();
                fail("we should never get here!");
            } catch (HttpClientErrorException e) {
                // expected
            }
        }

        // circuit is now tripped, but should it be?
        try {
            callingEndpointCircuitBreaker.decorateSupplier(() ->
                    restTemplate.getForEntity("/some/endpoint/10", JsonNode.class)
            ).get();
            fail("we should never get here!");
        } catch (CallNotPermittedException callNotPermittedException)  {
            assertEquals("call-endpoint", callNotPermittedException.getCausingCircuitBreakerName());
            assertSame(CircuitBreaker.State.OPEN, callingEndpointCircuitBreaker.getState());
        }
    }

```

\[Note: this code above will make more sense if you've read a [previous article on Resilience4j's circuit breaker](https://nickolasfisher.com/blog/configuring-testing-and-using-circuit-breakers-on-rest-api-calls-with-resilience4j) and downloaded the sample code from Github\]

If you want to not count specific types of exceptions as being errors, then the [CircuitBreakerConfig](https://javadoc.io/doc/io.github.resilience4j/resilience4j-circuitbreaker/1.2.0/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.html) provides you with a few different options. You can either [ignore the exceptions you want to no longer count](https://javadoc.io/static/io.github.resilience4j/resilience4j-circuitbreaker/1.2.0/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.Builder.html#ignoreException-java.util.function.Predicate-), or you can [be explicit about the kinds of exceptions you think are valid with recordException](https://javadoc.io/static/io.github.resilience4j/resilience4j-circuitbreaker/1.2.0/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.Builder.html#recordException-java.util.function.Predicate-).

In general I prefer to say "if it's an exception, then something is most likely wrong" unless it meets a specific number of things that I know are fine. So, in this example, a 404 response doesn't actually mean anything is wrong with the downstream service, and we can ignore it in the configuration like so:

```java
        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .ignoreException(throwable -> {
                    return throwable instanceof HttpClientErrorException;
                })
                .slidingWindowSize(10)
                .build();

```

Passing in a lambda as a **Predicate**, we know that **NotFound** is a subclass of **HttpClientErrorException**, and in general any 4xx response code is not enough to actively trip the circuit, and we can ignore it.

The full test that now proves this works is thus:

```java
    @Test
    public void excludingClientErrorExceptions_fromTheCount() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath("/some/endpoint/10");

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(404));

        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .ignoreException(throwable -> {
                    return throwable instanceof HttpClientErrorException;
                })
                .slidingWindowSize(10)
                .build();

        CircuitBreakerRegistry circuitBreakerRegistry =
                CircuitBreakerRegistry.of(circuitBreakerConfig);

        CircuitBreaker callingEndpointCircuitBreaker = circuitBreakerRegistry.circuitBreaker("call-endpoint");

        // before we ignored the exception above, this would trip the circuit
        for (int i = 1; i < 11; i++) {
            try {
                callingEndpointCircuitBreaker.decorateSupplier(() ->
                        restTemplate.getForEntity("/some/endpoint/10", JsonNode.class)
                ).get();
                fail("we should never get here!");
            } catch (HttpClientErrorException e) {
                // expected
            }
        }

        // the circuit doesn't trip
        try {
            callingEndpointCircuitBreaker.decorateSupplier(() ->
                    restTemplate.getForEntity("/some/endpoint/10", JsonNode.class)
            ).get();
            fail("we should never get here!");
        } catch (HttpClientErrorException httpClientErrorException)  {
            assertEquals(HttpStatus.NOT_FOUND, httpClientErrorException.getStatusCode());
            assertSame(CircuitBreaker.State.CLOSED, callingEndpointCircuitBreaker.getState());
        }
    }

```

And with that, you should be good to go.
