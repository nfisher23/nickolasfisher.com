---
title: "A Guide to Automatic Retries in Reactor"
date: 2020-08-16T16:22:09
draft: false
tags: [java, spring, reactive, testing, webflux]
---

The source code for this post [is available on GitHub](https://github.com/nfisher23/reactive-programming-webflux).

One of the nice things about a reactive programming model is there is a significantly lower risk of doomsday when things start getting latent all at once. You don't have threads upstream blocking and waiting for a response, therefore they won't all seize up and stop serving requests \[or they won't short circuit if you're using a resiliency library like hystrix\].

Reactor has a lot of extension points to pretty easily retry in the case of failure. I'll go through a couple of the options and provide some sample code to help you get started in this tutorial.

## The Example Project

I'm going to extend some sample code from a previous blog post on [testing WebClient using MockServer in Spring Boot Webflux](https://nickolasfisher.com/blog/how-to-use-mock-server-to-end-to-end-test-any-webclient-calls-in-spring-boot-webflux) to bootstrap us here. Recall, in that post, we had a really simple service:

```java
@Service
public class MyService {

    private final WebClient webClient;

    public MyService(WebClient webClient) {
        this.webClient = webClient;
    }

    public Flux<DownstreamResponseDTO> getAllPeople() {
        return this.webClient.get()
                .uri("/legacy/persons")
                .retrieve()
                .bodyToFlux(DownstreamResponseDTO.class);
    }
}

```

We were using MockServer and binding our webclient to that mock server with:

```java
public class MyServiceTest {

    private ClientAndServer mockServer;

    private MyService myService;

    private static final ObjectMapper serializer = new ObjectMapper();

    @BeforeEach
    public void setupMockServer() {
        mockServer = ClientAndServer.startClientAndServer(2001);
        myService = new MyService(WebClient.builder()
                .baseUrl("http://localhost:" + mockServer.getLocalPort()).build());
    }

    @AfterEach
    public void tearDownServer() {
        mockServer.stop();
    }

...the tests...
}

```

So let's add a test case using this framework. The test should setup mock server such that it:

- Returns a 5xx internal server error the first two times that we call it, simulating \[hopefully intermittent\] failures

- Recover and let a good request through on the third time we try it

We can make this happen by implementing our own custom [ExpectationResponseCallback](https://javadoc.io/static/org.mock-server/mockserver-core/5.6.1/org/mockserver/mock/action/ExpectationResponseCallback.html). Because java does not let you modify variables which were declared outside of the closure inside the closure, I'm also going to use an **AtomicInteger** because it has some convenience methods like **incrementAndGet**:

```java
        AtomicInteger counter = new AtomicInteger(0);
        mockServer.when(
                request()
                    .withMethod(HttpMethod.GET.name())
                    .withPath("/legacy/persons")
        ).respond(
                new ExpectationResponseCallback() {
                    @Override
                    public HttpResponse handle(HttpRequest httpRequest) throws Exception {
                        int attempt = counter.incrementAndGet();
                        if (attempt >= 2) {
                            return response().
                                    withBody(responseBody)
                                    .withContentType(MediaType.APPLICATION_JSON)
                                    .withStatusCode(HttpStatus.OK.value());
                        } else {
                            return response().withStatusCode(HttpStatus.INTERNAL_SERVER_ERROR.value());
                        }
                    }
                }
        );

```

Every time **GET "/legacy/persons"** is called, mock server will invoke our **ExpectationResponseCallback**, which is this case is looking for our **AtomicInteger** to increment past 2. Until it does, we will return a 500 Internal Server Error, and once it does we will return our response body.

All of the relevant code for this test can now be laid out like so:

```java
    private String getDownstreamResponseDTOAsString() throws JsonProcessingException {
        DownstreamResponseDTO downstreamResponseDTO = new DownstreamResponseDTO();

        downstreamResponseDTO.setLastName("last");
        downstreamResponseDTO.setFirstName("first");
        downstreamResponseDTO.setSsn("123-12-1231");
        downstreamResponseDTO.setDeepesetFear("alligators");

        return serializer.writeValueAsString(Arrays.asList(downstreamResponseDTO));
    }

    @Test
    public void retriesOnFailure() throws JsonProcessingException {
        String responseBody = getDownstreamResponseDTOAsString();

        AtomicInteger counter = new AtomicInteger(0);
        mockServer.when(
                request()
                    .withMethod(HttpMethod.GET.name())
                    .withPath("/legacy/persons")
        ).respond(
                new ExpectationResponseCallback() {
                    @Override
                    public HttpResponse handle(HttpRequest httpRequest) throws Exception {
                        int attempt = counter.incrementAndGet();
                        if (attempt >= 2) {
                            return response().
                                    withBody(responseBody)
                                    .withContentType(MediaType.APPLICATION_JSON)
                                    .withStatusCode(HttpStatus.OK.value());
                        } else {
                            return response().withStatusCode(HttpStatus.INTERNAL_SERVER_ERROR.value());
                        }
                    }
                }
        );

        List<DownstreamResponseDTO> responses = myService.getAllPeople().collectList().block();

        assertEquals(1, responses.size());
        assertEquals("first", responses.get(0).getFirstName());
        assertEquals("last", responses.get(0).getLastName());

        mockServer.verify(
                request().withMethod(HttpMethod.GET.name())
                        .withPath("/legacy/persons")
        );
    }

```

If you run this with:

```bash
mvn clean install

```

You will see the test fail, which makes sense because we have not yet created the code that actually retries.

## Doing Retries Now

A naive implementation of retrying could use some of the [built in Retry methods that ship with Reactor](https://projectreactor.io/docs/core/release/api/reactor/util/retry/Retry.html). We can get a passing test by instructing the **Flux** to retry up to three times:

```java
        return this.webClient.get()
                .uri("/legacy/persons")
                .retrieve()
                .bodyToFlux(DownstreamResponseDTO.class)
                .retryWhen(Retry.max(3));

```

While this is, err, fine, we should also want a bit more control over the backoff strategy so that we are not overwhelming the downstream service. This can be done with something like:

```java
        return this.webClient.get()
                .uri("/legacy/persons")
                .retrieve()
                .bodyToFlux(DownstreamResponseDTO.class)
                .retryWhen(Retry.backoff(3, Duration.ofMillis(250)));

```

This backoff strategy will automatically include a jitter for us so that a thundering herd of retries is unlikely to happen.

By invoking **backoff** we can then enter into a fluent API \[a [RetryBackoffSpec](https://projectreactor.io/docs/core/release/api/reactor/util/retry/RetryBackoffSpec.html)\], and can further customize it with something like:

```java
this.webClient.get()
.uri("/legacy/persons")
.retrieve()
.bodyToFlux(DownstreamResponseDTO.class)
.retryWhen(
    Retry.backoff(3, Duration.ofMillis(250))
        .minBackoff(Duration.ofMillis(100))
);

```

It's important to note that there is also [a Retry in reactor-extra](https://projectreactor.io/docs/extra/snapshot/api/reactor/retry/Retry.html), but this has now been deprecated in favor of the Retry functionality listed above, which ships with Reactor Core as of this article. You should use the library that ships with reactor core and save yourself a dependency.
