---
title: "How to use Mock Server to End to End Test Any WebClient Calls in Spring Boot Webflux"
date: 2020-08-08T22:44:14
draft: false
tags: [java, spring, reactive, testing, webflux]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/mocking-and-unit-testing).

[Mock Server](https://www.mock-server.com) is a really simple and straightforward way to actually let your application make downstream calls and intercept them. That level of abstraction is really nice to have, and gives at least me much more confidence that my code is actually working in a microservices environment.

There are a few different ways to [run MockServer with junit](https://www.mock-server.com/mock_server/running_mock_server.html), depending on the junit version and how much manual work you want to do. I'll go with the most portable setup for this tutorial.

## The Service, Using WebClient

I'm going to reuse code from my last blog post on [mocking dependencies and unit testing in webflux](https://nickolasfisher.com/blog/how-to-mock-dependencies-and-unit-test-in-spring-boot-webflux). If you recall, we had a really simple service with basically no logic:

```java
package com.nickolasfisher.testing.service;

import com.nickolasfisher.testing.dto.DownstreamResponseDTO;
import com.nickolasfisher.testing.dto.PersonDTO;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Flux;

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

To write a test for this, let's first get mock server setting up properly. You will want to add the mock server dependency to your **pom.xml** if you're using maven, or your **build.gradle** if you're using gradle:

```xml
<dependency>
    <groupId>org.mock-server</groupId>
    <artifactId>mockserver-netty</artifactId>
    <version>5.11.1</version>
</dependency>

```

And create the test class somewhere in **src/test/...**. We will start and stop mock server as boilerplate:

```java
public class MyServiceTest {

    private ClientAndServer mockServer;

    @BeforeEach
    public void setupMockServer() {
        mockServer = ClientAndServer.startClientAndServer(2001);
    }

    @AfterEach
    public void tearDownServer() {
        mockServer.stop();
    }
}

```

I picked a static port in this case, but it's probably more robust to have java find you an available TCP port. Since we're using Spring Boot, you should check out [SocketUtils to find an available TCP port](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/util/SocketUtils.html#findAvailableTcpPort) for you.

There are two things we would want to assert in a happy path test: first, that we are actually making the request and second, we are deserializing the response properly and it is making it into the **Flux**. One way to do this is by forcing the downstream call to block for us:

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

    @Test
    public void testTheThing() throws JsonProcessingException {
        String responseBody = getDownstreamResponseDTOAsString();
        mockServer.when(
                request()
                    .withMethod(HttpMethod.GET.name())
                    .withPath("/legacy/persons")
        ).respond(
                response()
                    .withStatusCode(HttpStatus.OK.value())
                    .withContentType(MediaType.APPLICATION_JSON)
                    .withBody(responseBody)
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

    private String getDownstreamResponseDTOAsString() throws JsonProcessingException {
        DownstreamResponseDTO downstreamResponseDTO = new DownstreamResponseDTO();

        downstreamResponseDTO.setLastName("last");
        downstreamResponseDTO.setFirstName("first");
        downstreamResponseDTO.setSsn("123-12-1231");
        downstreamResponseDTO.setDeepesetFear("alligators");

        return serializer.writeValueAsString(Arrays.asList(downstreamResponseDTO));
    }
}

```

We are verifying that at least part of the response got loaded into our POJO properly with:

```java
assertEquals(1, responses.size());
assertEquals("first", responses.get(0).getFirstName());
assertEquals("last", responses.get(0).getLastName());

```

And we are verifying the request was made with:

```java
mockServer.verify(
        request().withMethod(HttpMethod.GET.name())
            .withPath("/legacy/persons")
);

```

Note that you would never want to use those blocking methods in any production code, but for testing it helps simplify our life and gives us a high degree of confidence we are doing things properly.

As a reminder, you can [checkout and use this code on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/mocking-and-unit-testing).
