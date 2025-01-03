---
title: "How to Automatically Retry on a Webclient Timeout in Spring Boot Webflux"
date: 2020-10-01T00:00:00
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/api-calls-and-resilience).

Intermittent network flapping, or any one downstream host of several clones responding slowly, is a not uncommon thing that happens in a microservices architecture, especially if you&#39;re using java applications, where the JIT compiler can often make initial requests slower than they ought to be.

Depending on the request that you&#39;re making, it can often be retried effectively to smooth out these effects to your consumer. Doing so in a straightforward and declarative way will be the subject of this post.

### The App

I&#39;m going to build off of some work in [a previous blog post about fallbacks](https://nickolasfisher.com/blog/How-to-Have-a-Fallback-on-Errors-Calling-Downstream-Services-in-Spring-Boot-Webflux). You&#39;ll recall that we had setup a WebClient like so:

``` java
@Configuration
public class Config {

    @Bean(&#34;service-a-web-client&#34;)
    public WebClient serviceAWebClient() {
        HttpClient httpClient = HttpClient.create().tcpConfiguration(tcpClient -&gt;
                tcpClient.option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 1000)
                        .doOnConnected(connection -&gt; connection.addHandlerLast(new ReadTimeoutHandler(1000, TimeUnit.MILLISECONDS)))
        );

        return WebClient.builder()
                .baseUrl(&#34;http://your-base-url.com&#34;)
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .build();
    }
}

```

This **WebClient** already has a timeout of 1 second configured, which in many cases is quite conservative \[well written, performance focused services usually respond much faster than that\].

### Setting up the retry

I&#39;ll also steal our DTO from the last post:

``` java
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

With this, let&#39;s set up a barebones services that will soon contain the code we&#39;re looking for:

``` java
@Service
public class RetryService {
    private final WebClient serviceAWebClient;

    public RetryService(@Qualifier(&#34;service-a-web-client&#34;) WebClient serviceAWebClient) {
        this.serviceAWebClient = serviceAWebClient;
    }

    public Mono&lt;WelcomeMessage&gt; getWelcomeMessageAndHandleTimeout(String locale) {
        return Mono.empty();
    }
}
```

This code doesn&#39;t do anything yet. Now let&#39;s make a test class, configured with the familiar MockServer setup that we&#39;ve leveraged before:

``` java
@ExtendWith(MockServerExtension.class)
public class RetryServiceIT {

    public static final int WEBCLIENT_TIMEOUT = 50;
    private final ClientAndServer clientAndServer;

    private RetryService retryService;
    private WebClient mockWebClient;

    public RetryServiceIT(ClientAndServer clientAndServer) {
        this.clientAndServer = clientAndServer;
        HttpClient httpClient = HttpClient.create()
                .tcpConfiguration(tcpClient -&gt;
                        tcpClient.option(ChannelOption.CONNECT_TIMEOUT_MILLIS, WEBCLIENT_TIMEOUT)
                                .doOnConnected(connection -&gt; connection.addHandlerLast(
                                        new ReadTimeoutHandler(WEBCLIENT_TIMEOUT, TimeUnit.MILLISECONDS))
                                )
                );

        this.mockWebClient = WebClient.builder()
                .baseUrl(&#34;http://localhost:&#34; &#43; this.clientAndServer.getPort())
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .build();
    }

    @BeforeEach
    public void setup() {
        this.retryService = new RetryService(mockWebClient);
    }

    @AfterEach
    public void clearExpectations() {
        this.clientAndServer.reset();
    }

    @Test
    public void retryOnTimeout() {
        AtomicInteger counter = new AtomicInteger();
        HttpRequest expectedRequest = request()
                .withPath(&#34;/locale/en_US/message&#34;)
                .withMethod(HttpMethod.GET.name());

        this.clientAndServer.when(
                expectedRequest
        ).respond(
                httpRequest -&gt; {
                    if (counter.incrementAndGet() &lt; 2) {
                        Thread.sleep(WEBCLIENT_TIMEOUT &#43; 10);
                    }
                    return HttpResponse.response()
                            .withBody(&#34;{\&#34;message\&#34;: \&#34;hello\&#34;}&#34;)
                            .withContentType(MediaType.APPLICATION_JSON);
                }
        );

        StepVerifier.create(retryService.getWelcomeMessageAndHandleTimeout(&#34;en_US&#34;))
                .expectNextMatches(welcomeMessage -&gt; &#34;hello&#34;.equals(welcomeMessage.getMessage()))
                .verifyComplete();

        this.clientAndServer.verify(expectedRequest, VerificationTimes.exactly(3));
    }
}

```

This code:

1. Starts by looking for a GET request at the endpoint **/locale/en\_US/message**
2. Anything that matches that request path and HTTP method will then leverage an [ExpectationResponseCallback](https://javadoc.io/static/org.mock-server/mockserver-core/5.6.1/org/mockserver/mock/action/ExpectationResponseCallback.html) to sleep for 10 milliseconds longer than our **WebClient** is configured to timeout on for the first two requests
3. After the first two requests are completed, the response will immediately return
4. We verify, using [StepVerifier](https://projectreactor.io/docs/test/release/api/index.html?reactor/test/StepVerifier.html), that there is one item in the **Mono** and that item is deserialized correctly.
5. We then assert that this endpoint was called three times, meaning the first two would have timed out, and the final one was successful.

Now, following TDD, let&#39;s write code that passes this test:

``` java
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

```

This code:

1. Makes a GET request to the locale endpoint specified, passing in the **locale** argument so that it gets interpolated.
2. Deserializes the response into a **WelcomeMessage**
3. If that mono fails to complete, it will consult the specified **retryWhen** declaration.
4. We specify that any exception which is of type **TimeoutException** should be retried twice, for a total of three attempts.

If you now run the test, it will pass. Remember to [check out the source code on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/api-calls-and-resilience)!


