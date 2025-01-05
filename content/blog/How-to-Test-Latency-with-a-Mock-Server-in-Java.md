---
title: "How to Test Latency with a Mock Server in Java"
date: 2021-05-01T18:12:45
draft: false
tags: [java, spring, testing]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/java-failure-and-resilience).

Very often, you will want to test service api clients using a [Mock Server](https://www.mock-server.com/) \[for example, [testing the spring webclient with mockserver](https://nickolasfisher.com/blog/how-to-use-mock-server-to-end-to-end-test-any-webclient-calls-in-spring-boot-webflux)\]. And since network latency is a fact of life, not something we can merely ignore, actually injecting some latency to simulate timeouts will give us greater confidence that our system will behave as expected.

### Boilerplate for mock server

If we start by following the instructions for setting up mock server, we can leverage JUnit 5 and use annotations:

```java
@ExtendWith(MockServerExtension.class)
public class MockServerTimeoutTest {

    private ClientAndServer clientAndServer;

    public MockServerTimeoutTest(ClientAndServer clientAndServer) {
        this.clientAndServer = clientAndServer;

    }

    @AfterEach
    public void reset() {
        this.clientAndServer.reset();
    }
}

```

This automatically starts mock server for us on a random port, and the **@AfterEach** annotation ensures we clear the expectations for mock server, which should give us improved consistency \[when one test fails, it doesn't affect the other tests\].

A simple example test, using **RestTemplate**, could then look like this:

```java
    @Test
    public void basicRestTemplateExample() {
        RestTemplate restTemplate = new RestTemplateBuilder()
                .rootUri("http://localhost:" + clientAndServer.getPort())
                .build();

        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath("/some/endpoint/10");

        HttpResponse mockResponse = HttpResponse.response()
                .withBody("{\"message\": \"hello\"}")
                .withContentType(MediaType.APPLICATION_JSON)
                .withStatusCode(200);

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(mockResponse);

        ResponseEntity<JsonNode> responseEntity = restTemplate.getForEntity("/some/endpoint/10", JsonNode.class);

        assertEquals("hello", responseEntity.getBody().get("message").asText());
    }

```

This just makes a request to a canned endpoint **"/some/endpoint/10"** and returns a canned response. We then verify that we deserialize the response properly.

### Testing for Latency

Now the question becomes, what happens when we encounter latency? Do we have our timeouts configured properly, and if so can we handle an unexpected increase in latency gracefully?

Instrumenting something like that with mock server is pretty straightforward, we just leverage an [ExpectationResponseCalback](https://javadoc.io/static/org.mock-server/mockserver-core/5.6.1/org/mockserver/mock/action/ExpectationResponseCallback.html), which allows us to run whatever code we want once we get a matching request. This is a functional interface and we can therefore write a little lambda, the condensed version of just sleeping once we get the request can look like so:

```java
        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(httpRequest -> {
                            Thread.sleep(150);
                            return mockResponse;
                        }
                );

```

And a full test that leverages that to prove it actually works can be like so:

```java
    @Test
    public void latencyInMockServer() {
        RestTemplate restTemplateWithSmallTimeout = new RestTemplateBuilder()
                .rootUri("http://localhost:" + clientAndServer.getPort())
                .setConnectTimeout(Duration.of(50, ChronoUnit.MILLIS))
                .setReadTimeout(Duration.of(80, ChronoUnit.MILLIS))
                .build();

        RestTemplate restTemplateWithBigTimeout = new RestTemplateBuilder()
                .rootUri("http://localhost:" + clientAndServer.getPort())
                .setConnectTimeout(Duration.of(50, ChronoUnit.MILLIS))
                .setReadTimeout(Duration.of(250, ChronoUnit.MILLIS))
                .build();

        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath("/some/endpoint/10");

        HttpResponse mockResponse = HttpResponse.response()
                .withBody("{\"message\": \"hello\"}")
                .withContentType(MediaType.APPLICATION_JSON)
                .withStatusCode(200);

        this.clientAndServer
                .when(expectedFirstRequest)
                .respond(httpRequest -> {
                            Thread.sleep(150);
                            return mockResponse;
                        }
                );

        try {
            restTemplateWithSmallTimeout.getForEntity("/some/endpoint/10", JsonNode.class);
            fail("We should never reach this line!");
        } catch (ResourceAccessException resourceAccessException) {
            assertEquals("Read timed out", resourceAccessException.getCause().getMessage());
        }

        ResponseEntity<JsonNode> jsonNodeResponseEntity = restTemplateWithBigTimeout
                .getForEntity("/some/endpoint/10", JsonNode.class);

        assertEquals(200, jsonNodeResponseEntity.getStatusCode().value());
        assertEquals("hello", jsonNodeResponseEntity.getBody().get("message").asText());
    }

```

All we do here is assert that we're getting a read timeout when the timeout is lower than how long our mock server will take to respond, and that when it's bigger than the amount of time it takes to respond we are in good shape.

It's important to note that just bumping up the timeouts is not a recommended solution for production code, but this way we can start to test some robust resiliency mechanisms with confidence.
