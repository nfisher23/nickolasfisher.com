---
title: "How to Prevent Certain Exceptions from Tripping a Resilience4j Circuit"
date: 2021-05-01T00:00:00
draft: false
---

The source code for this article [can be found on Github](https://github.com/nfisher23/java-failure-and-resilience).

The Resilience4j circuit breaker by default considers any exception thrown inside of the **Supplier** as a failure. If over 50% of the calls are failures and the rolling window max size is met, then it will prevent any future calls from going through.

It&#39;s not uncommon to throw exceptions as a part of normal business logic--they might be thrown because of an _exceptional circumstance_, but that doesn&#39;t mean that there is an error or something wrong with the downstream resource you&#39;re trying to interact with. For example, Spring&#39;s **RestTemplate** will throw an exception on a 4xx response code, and this will by default trip the circuit and prevent future calls from going through:

``` java
    @Test
    public void clientErrorException_stillTripsTheCircuit() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath(&#34;/some/endpoint/10&#34;);

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(404));

        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .slidingWindowSize(10)
                .build();

        CircuitBreakerRegistry circuitBreakerRegistry =
                CircuitBreakerRegistry.of(circuitBreakerConfig);

        CircuitBreaker callingEndpointCircuitBreaker = circuitBreakerRegistry.circuitBreaker(&#34;call-endpoint&#34;);

        // force the circuit to trip
        for (int i = 1; i &lt; 11; i&#43;&#43;) {
            try {
                callingEndpointCircuitBreaker.decorateSupplier(() -&gt;
                        restTemplate.getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
                ).get();
                fail(&#34;we should never get here!&#34;);
            } catch (HttpClientErrorException e) {
                // expected
            }
        }

        // circuit is now tripped, but should it be?
        try {
            callingEndpointCircuitBreaker.decorateSupplier(() -&gt;
                    restTemplate.getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
            ).get();
            fail(&#34;we should never get here!&#34;);
        } catch (CallNotPermittedException callNotPermittedException)  {
            assertEquals(&#34;call-endpoint&#34;, callNotPermittedException.getCausingCircuitBreakerName());
            assertSame(CircuitBreaker.State.OPEN, callingEndpointCircuitBreaker.getState());
        }
    }

```

\[Note: this code above will make more sense if you&#39;ve read a [previous article on Resilience4j&#39;s circuit breaker](https://nickolasfisher.com/blog/Configuring-Testing-and-Using-Circuit-Breakers-on-Rest-API-calls-with-Resilience4j) and downloaded the sample code from Github\]

If you want to not count specific types of exceptions as being errors, then the [CircuitBreakerConfig](https://javadoc.io/doc/io.github.resilience4j/resilience4j-circuitbreaker/1.2.0/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.html) provides you with a few different options. You can either [ignore the exceptions you want to no longer count](https://javadoc.io/static/io.github.resilience4j/resilience4j-circuitbreaker/1.2.0/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.Builder.html#ignoreException-java.util.function.Predicate-), or you can [be explicit about the kinds of exceptions you think are valid with recordException](https://javadoc.io/static/io.github.resilience4j/resilience4j-circuitbreaker/1.2.0/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.Builder.html#recordException-java.util.function.Predicate-).

In general I prefer to say &#34;if it&#39;s an exception, then something is most likely wrong&#34; unless it meets a specific number of things that I know are fine. So, in this example, a 404 response doesn&#39;t actually mean anything is wrong with the downstream service, and we can ignore it in the configuration like so:

``` java
        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .ignoreException(throwable -&gt; {
                    return throwable instanceof HttpClientErrorException;
                })
                .slidingWindowSize(10)
                .build();

```

Passing in a lambda as a **Predicate**, we know that **NotFound** is a subclass of **HttpClientErrorException**, and in general any 4xx response code is not enough to actively trip the circuit, and we can ignore it.

The full test that now proves this works is thus:

``` java
    @Test
    public void excludingClientErrorExceptions_fromTheCount() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath(&#34;/some/endpoint/10&#34;);

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(404));

        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .ignoreException(throwable -&gt; {
                    return throwable instanceof HttpClientErrorException;
                })
                .slidingWindowSize(10)
                .build();

        CircuitBreakerRegistry circuitBreakerRegistry =
                CircuitBreakerRegistry.of(circuitBreakerConfig);

        CircuitBreaker callingEndpointCircuitBreaker = circuitBreakerRegistry.circuitBreaker(&#34;call-endpoint&#34;);

        // before we ignored the exception above, this would trip the circuit
        for (int i = 1; i &lt; 11; i&#43;&#43;) {
            try {
                callingEndpointCircuitBreaker.decorateSupplier(() -&gt;
                        restTemplate.getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
                ).get();
                fail(&#34;we should never get here!&#34;);
            } catch (HttpClientErrorException e) {
                // expected
            }
        }

        // the circuit doesn&#39;t trip
        try {
            callingEndpointCircuitBreaker.decorateSupplier(() -&gt;
                    restTemplate.getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
            ).get();
            fail(&#34;we should never get here!&#34;);
        } catch (HttpClientErrorException httpClientErrorException)  {
            assertEquals(HttpStatus.NOT_FOUND, httpClientErrorException.getStatusCode());
            assertSame(CircuitBreaker.State.CLOSED, callingEndpointCircuitBreaker.getState());
        }
    }

```

And with that, you should be good to go.


