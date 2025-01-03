---
title: "Configuring, Testing, and Using Circuit Breakers on Rest API calls with Resilience4j"
date: 2021-05-01T19:06:23
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/java-failure-and-resilience).

The circuit breaker pattern, popularized by Netflix \[using Hystrix\], exists for a couple of reasons, the most prominent being that it reduces load on a downstream service when it is not responding properly \[presumably because it&#39;s under duress\]. By wrapping operations that might fail and get overloaded in a circuit breaker, we can prematurely prevent cascading failure and stop overloading those services.

### Testing the Circuit Breaker

To start with, we will want to build off of a previous article that demonstrates how to [setup a Mock Server instance for testing](https://nickolasfisher.com/blog/How-to-Test-Latency-with-a-Mock-Server-in-Java). If you&#39;re using JUnit5, we can start like so:

```java
@ExtendWith(MockServerExtension.class)
public class CircuitBreakerTest {

    private ClientAndServer clientAndServer;

    private RestTemplate restTemplate;

    public CircuitBreakerTest(ClientAndServer clientAndServer) {
        this.clientAndServer = clientAndServer;
        this.restTemplate = new RestTemplateBuilder()
                .rootUri(&#34;http://localhost:&#34; &#43; clientAndServer.getPort())
                .build();
    }

    @AfterEach
    public void reset() {
        this.clientAndServer.reset();
    }
}

```

We can now get some more boilerplate out of the way: let&#39;s just respond with a 500 status code on every request that we&#39;re about to make:

```java
    @Test
    public void basicConfig_nothingHappensIfSlidingWindowNotFilled() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath(&#34;/some/endpoint/10&#34;);

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(500));

        ...code to come...
    }

```

And with that, we can actually start using the circuit breaker to make our applications better at handling failure.

### Configuring and Using the Circuit Breaker

The [circuit breaker configuration options](https://resilience4j.readme.io/docs/circuitbreaker) are pretty varied and deserve their own set of articles. In most situations, the defaults are going to be reasonable. One that would make testing this very hard is the **slidingWindowSize**. Because this is set to 100 by default, we would have to call this 100 times before the circuit is eligible to be tripped \[OPEN\]. Therefore I&#39;m going to make it 10 instead:

```java
        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .slidingWindowSize(10)
                .build();

        CircuitBreakerRegistry circuitBreakerRegistry =
                CircuitBreakerRegistry.of(circuitBreakerConfig);

        CircuitBreaker callingEndpointCircuitBreaker = circuitBreakerRegistry.circuitBreaker(&#34;call-endpoint&#34;);

```

As is a common theme among Resilience4j&#39;s tooling, you need a registry, which takes in configuration. Then, to actually get an object you can work with you simply pull from the registry using a string to identify the name.

We can use a circuit breaker by passing in a lambda function containing the code we actually want to run, so that the circuit breaker is decorating it:

```java
                callingEndpointCircuitBreaker.decorateSupplier(() -&gt;
                        restTemplate.getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
                ).get();

```

But this doesn&#39;t tell us anything about the circuit breaker itself, because as we have it configured this call is just going to fail and we&#39;re going to get an exception. We can verify that a circuit trips once the slidingWindowSize has been reached \[configured to 10\] and then there is a greater than 50% error rate for the underlying operation, which in this case is a network call:

```java
        // force the circuit to trip
        for (int i = 1; i &lt; 11; i&#43;&#43;) {
            try {
                callingEndpointCircuitBreaker.decorateSupplier(() -&gt;
                        restTemplate.getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
                ).get();
                fail(&#34;we should never get here!&#34;);
            } catch (HttpServerErrorException e) {
                // expected
            }
        }

        // circuit is now tripped
        try {
            callingEndpointCircuitBreaker.decorateSupplier(() -&gt;
                    restTemplate.getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
            ).get();
            fail(&#34;we should never get here!&#34;);
        } catch (CallNotPermittedException callNotPermittedException)  {
            assertEquals(&#34;call-endpoint&#34;, callNotPermittedException.getCausingCircuitBreakerName());
            assertSame(CircuitBreaker.State.OPEN, callingEndpointCircuitBreaker.getState());
        }

```

Here we use the circuit breaker decorator to call our downstream service \[using mock server to simulate the service\]. After ten attempts, because the error percentage was over 50%, we should see a new kind of error--one generated by the **CircuitBreaker** itself and not by the underlying code that it is decorating.

To sum this up, the code for the entire test can be seen here:

```java
    @Test
    public void basicConfig_nothingHappensIfSlidingWindowNotFilled() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath(&#34;/some/endpoint/10&#34;);

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(500));

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
            } catch (HttpServerErrorException e) {
                // expected
            }
        }

        // circuit is now tripped
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

And with that, you should be good to go.
