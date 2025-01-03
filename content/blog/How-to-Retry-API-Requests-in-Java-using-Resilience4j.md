---
title: "How to Retry API Requests in Java using Resilience4j"
date: 2021-05-01T18:34:59
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/java-failure-and-resilience).

When you&#39;re working with distributed systems, it is often the case that some clones of a service running can be slow to respond, while still others are functioning perfectly normally. Therefore, when you just hit a load balancer and the load balancer chooses a backend, it can sometimes be beneficial to retry the request. Other things like periodic and small database stalls or random GC stop-the-worlds are examples where retries can smooth the experience for the client of your service.

While writing code that simply retries a request a number of times isn&#39;t that complicated, there is also an entire ecosystem of resilience in java in the form of [resilience4j](https://github.com/resilience4j/resilience4j). It provides a lot of good tools, and declarative retries with several configuration options is one of them.

### Simulate Intermittent Latency for a Repeatable Test

To build off of a previous article on how to simulate latency using Mock Server in Java, we can modify that code slightly to not time out every single time but to only time out intermittently. Because we are writing a test that we want to be repeatable, rather than use a random number generator I&#39;m just going to use a counter, in this case just an **AtomicInteger**:

```java
       AtomicInteger timesCalled = new AtomicInteger(0);
        this.clientAndServer
            .when(expectedFirstRequest)
            .respond(httpRequest -&gt; {
                    if (timesCalled.incrementAndGet() &lt;= 2) {
                        // simulate latency
                        Thread.sleep(150);
                    }
                    return mockResponse;
                }
            );

```

With this code in mind, what we will want to do first is ensure that our rest client has a timeout which is configured lower than the simulated latency, or we aren&#39;t going to be testing what we think we are testing:

```java
       RestTemplate restTemplate = new RestTemplateBuilder()
                .rootUri(&#34;http://localhost:&#34; &#43; clientAndServer.getPort())
                .setConnectTimeout(Duration.of(50, ChronoUnit.MILLIS))
                .setReadTimeout(Duration.of(80, ChronoUnit.MILLIS))
                .build();

```

The full code for generating expectations and simulating latency can then look like this:

```java
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath(&#34;/some/endpoint/10&#34;);

        HttpResponse mockResponse = HttpResponse.response()
                .withBody(&#34;{\&#34;message\&#34;: \&#34;hello\&#34;}&#34;)
                .withContentType(MediaType.APPLICATION_JSON)
                .withStatusCode(200);

        AtomicInteger timesCalled = new AtomicInteger(0);
        this.clientAndServer
            .when(expectedFirstRequest)
            .respond(httpRequest -&gt; {
                    if (timesCalled.incrementAndGet() &lt;= 2) {
                        // simulate latency
                        Thread.sleep(150);
                    }
                    return mockResponse;
                }
            );

```

With this in place, we can start playing with Resilience4j&#39;s Retry library.

### An Example Using Retry

The core concepts of using Retry are pretty simple, you need a **RetryConfig** and a **RetryRegistry**, and from that you can get an instance of **Retry**. The **Retry** object that you get from the registry will have the configuration passed into the registry. For this case, we&#39;re going to specify a maximum number of attempts as 3, and we&#39;re going to further say to wait 100 milliseconds between each request:

```java
       RetryConfig retryConfig = RetryConfig.custom()
                .maxAttempts(3)
                .waitDuration(Duration.ofMillis(100))
                .build();

        RetryRegistry retryRegistry = RetryRegistry.of(retryConfig);

        Retry retry = retryRegistry.retry(&#34;some-endpoint&#34;);

```

We can then use it to retry our api call like so:

```java
       ResponseEntity&lt;JsonNode&gt; jsonNodeResponseEntity = Retry.decorateCheckedSupplier(
                retry,
                () -&gt; restTemplate
                    .getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
        )
                .unchecked()
                .get();

```

By specifying unchecked in the fluent api, I&#39;m saying &#34;don&#39;t make me deal with checked exceptions&#34;. **unchecked** returns a [Function0](https://www.javadoc.io/static/io.vavr/vavr/0.9.2/io/vavr/Function0.html) which has some yet further fluent options to work with.

To round out the entire test including assertions that our retry worked successfully after three attempts, here is the test method:

```java
    @Test
    public void retryOnLatency() {
        RestTemplate restTemplate = new RestTemplateBuilder()
                .rootUri(&#34;http://localhost:&#34; &#43; clientAndServer.getPort())
                .setConnectTimeout(Duration.of(50, ChronoUnit.MILLIS))
                .setReadTimeout(Duration.of(80, ChronoUnit.MILLIS))
                .build();

        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath(&#34;/some/endpoint/10&#34;);

        HttpResponse mockResponse = HttpResponse.response()
                .withBody(&#34;{\&#34;message\&#34;: \&#34;hello\&#34;}&#34;)
                .withContentType(MediaType.APPLICATION_JSON)
                .withStatusCode(200);

        AtomicInteger timesCalled = new AtomicInteger(0);
        this.clientAndServer
            .when(expectedFirstRequest)
            .respond(httpRequest -&gt; {
                    if (timesCalled.incrementAndGet() &lt;= 2) {
                        // simulate latency
                        Thread.sleep(150);
                    }
                    return mockResponse;
                }
            );

        RetryConfig retryConfig = RetryConfig.custom()
                .maxAttempts(3)
                .waitDuration(Duration.ofMillis(100))
                .build();

        RetryRegistry retryRegistry = RetryRegistry.of(retryConfig);

        Retry retry = retryRegistry.retry(&#34;some-endpoint&#34;);

        ResponseEntity&lt;JsonNode&gt; jsonNodeResponseEntity = Retry.decorateCheckedSupplier(
                retry,
                () -&gt; restTemplate
                    .getForEntity(&#34;/some/endpoint/10&#34;, JsonNode.class)
        )
                .unchecked().apply();

        assertEquals(3, timesCalled.get());
        assertEquals(200, jsonNodeResponseEntity.getStatusCode().value());
        assertEquals(&#34;hello&#34;, jsonNodeResponseEntity.getBody().get(&#34;message&#34;).asText());
    }

```

We verify that we called our mock server exactly three times, and that the final response was indeed a 200 response code and the expected body.

And with that, you should be good to go.
