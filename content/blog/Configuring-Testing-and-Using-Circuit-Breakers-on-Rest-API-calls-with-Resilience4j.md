---
title: "Configuring, Testing, and Using Circuit Breakers on Rest API calls with Resilience4j"
date: 2021-05-01T19:06:23
draft: false
tags: [java, spring, resilience]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/java-failure-and-resilience).

The circuit breaker pattern, popularized by Netflix \[using Hystrix\], exists for a couple of reasons, the most prominent being that it reduces load on a downstream service when it is not responding properly \[presumably because it's under duress\]. By wrapping operations that might fail and get overloaded in a circuit breaker, we can prematurely prevent cascading failure and stop overloading those services.

### Testing the Circuit Breaker

To start with, we will want to build off of a previous article that demonstrates how to [setup a Mock Server instance for testing](https://nickolasfisher.com/blog/How-to-Test-Latency-with-a-Mock-Server-in-Java). If you're using JUnit5, we can start like so:

```java
@ExtendWith(MockServerExtension.class)
public class CircuitBreakerTest {

    private ClientAndServer clientAndServer;

    private RestTemplate restTemplate;

    public CircuitBreakerTest(ClientAndServer clientAndServer) {
        this.clientAndServer = clientAndServer;
        this.restTemplate = new RestTemplateBuilder()
                .rootUri("http://localhost:" + clientAndServer.getPort())
                .build();
    }

    @AfterEach
    public void reset() {
        this.clientAndServer.reset();
    }
}

```

We can now get some more boilerplate out of the way: let's just respond with a 500 status code on every request that we're about to make:

```java
    @Test
    public void basicConfig_nothingHappensIfSlidingWindowNotFilled() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath("/some/endpoint/10");

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(500));

        ...code to come...
    }

```

And with that, we can actually start using the circuit breaker to make our applications better at handling failure.

### Configuring and Using the Circuit Breaker

The [circuit breaker configuration options](https://resilience4j.readme.io/docs/circuitbreaker) are pretty varied and deserve their own set of articles. In most situations, the defaults are going to be reasonable. One that would make testing this very hard is the **slidingWindowSize**. Because this is set to 100 by default, we would have to call this 100 times before the circuit is eligible to be tripped \[OPEN\]. Therefore I'm going to make it 10 instead:

```java
        CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig
                .custom()
                .slidingWindowSize(10)
                .build();

        CircuitBreakerRegistry circuitBreakerRegistry =
                CircuitBreakerRegistry.of(circuitBreakerConfig);

        CircuitBreaker callingEndpointCircuitBreaker = circuitBreakerRegistry.circuitBreaker("call-endpoint");

```

As is a common theme among Resilience4j's tooling, you need a registry, which takes in configuration. Then, to actually get an object you can work with you simply pull from the registry using a string to identify the name.

We can use a circuit breaker by passing in a lambda function containing the code we actually want to run, so that the circuit breaker is decorating it:

```java
                callingEndpointCircuitBreaker.decorateSupplier(() ->
                        restTemplate.getForEntity("/some/endpoint/10", JsonNode.class)
                ).get();

```

But this doesn't tell us anything about the circuit breaker itself, because as we have it configured this call is just going to fail and we're going to get an exception. We can verify that a circuit trips once the slidingWindowSize has been reached \[configured to 10\] and then there is a greater than 50% error rate for the underlying operation, which in this case is a network call:

```java
        // force the circuit to trip
        for (int i = 1; i < 11; i++) {
            try {
                callingEndpointCircuitBreaker.decorateSupplier(() ->
                        restTemplate.getForEntity("/some/endpoint/10", JsonNode.class)
                ).get();
                fail("we should never get here!");
            } catch (HttpServerErrorException e) {
                // expected
            }
        }

        // circuit is now tripped
        try {
            callingEndpointCircuitBreaker.decorateSupplier(() ->
                    restTemplate.getForEntity("/some/endpoint/10", JsonNode.class)
            ).get();
            fail("we should never get here!");
        } catch (CallNotPermittedException callNotPermittedException)  {
            assertEquals("call-endpoint", callNotPermittedException.getCausingCircuitBreakerName());
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
                .withPath("/some/endpoint/10");

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(HttpResponse.response().withStatusCode(500));

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
            } catch (HttpServerErrorException e) {
                // expected
            }
        }

        // circuit is now tripped
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

And with that, you should be good to go.
