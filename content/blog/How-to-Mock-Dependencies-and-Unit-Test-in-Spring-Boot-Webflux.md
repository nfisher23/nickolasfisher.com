---
title: "How to Mock Dependencies and Unit Test in Spring Boot Webflux"
date: 2020-08-08T22:14:53
draft: false
tags: [java, spring, reactive, webflux]
---

The source code for this post can be found [on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/mocking-and-unit-testing).

The most straightforward way to write unit tests in spring boot webflux is to leverage [project reactor's StepVerifier](https://projectreactor.io/docs/test/release/api/reactor/test/StepVerifier.html). StepVerifier allows you to pull each item in a **Flux** or the only potential item in a **Mono** and make assertions about each item as it's pulled through the chain, or make assertions about certain errors that should be thrown in the process. I'm going to quickly walk you through an example integrating mockito with it and webflux.

## Bootstrap the Project

We're going to make a single endpoint whose job is to filter the results from a downstream call to prevent sensitive information from travelling arbitrarily to the client.

Go to the [spring initializr](https://start.spring.io/) and select the reactive web option. After you have unzipped it, let's set up our data models, service, web client config, and controller:

```java
public class DownstreamResponseDTO {
    private String firstName;
    private String lastName;
    private String ssn;
    private String deepesetFear;

    public String getFirstName() {
        return firstName;
    }

    public void setFirstName(String firstName) {
        this.firstName = firstName;
    }

    public String getLastName() {
        return lastName;
    }

    public void setLastName(String lastName) {
        this.lastName = lastName;
    }

    public String getSsn() {
        return ssn;
    }

    public void setSsn(String ssn) {
        this.ssn = ssn;
    }

    public String getDeepesetFear() {
        return deepesetFear;
    }

    public void setDeepesetFear(String deepesetFear) {
        this.deepesetFear = deepesetFear;
    }
}

....different file...

public class PersonDTO {
    private String firstName;
    private String lastName;

    public String getFirstName() {
        return firstName;
    }

    public void setFirstName(String firstName) {
        this.firstName = firstName;
    }

    public String getLastName() {
        return lastName;
    }

    public void setLastName(String lastName) {
        this.lastName = lastName;
    }
}

```

As we can see, the downstream service will respond with the users SSN and deepest fear. Let's say for the sake of this example that our clients don't need that information. Here's our controller:

```java
@RestController
public class MyController {

    private final MyService service;

    public MyController(MyService service) {
        this.service = service;
    }

    @GetMapping("/persons")
    public Flux<PersonDTO> getPersons() {
        return service.getAllPeople().map(downstreamResponseDTO -> {
            PersonDTO personDTO = new PersonDTO();

            personDTO.setFirstName(downstreamResponseDTO.getFirstName());
            personDTO.setLastName(downstreamResponseDTO.getLastName());

            return personDTO;
        });
    }
}

```

And our service:

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

Finally, the webclient config, which is actually not useful to this tutorial but we can include for completeness:

```java
@Configuration
public class MyConfig {

    @Bean
    public WebClient webClient() {
        return WebClient.builder()
                .baseUrl("http://localhost:9000")
                .defaultHeader(CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .build();
    }
}

```

Alright. Now, to write a unit test for this, we will mock out our service layer and have it respond with some mocked out values. This is pretty straightforward to do with mockito:

```java
public class MyControllerTest {
    private MyService myServiceMock;

    private MyController myController;

    @BeforeEach
    public void setup() {
        myServiceMock = Mockito.mock(MyService.class);
        myController = new MyController(myServiceMock);
    }

    @Test
    public void verifyTransformsCorrectly() {
        DownstreamResponseDTO downstreamResponseDTO_1 = new DownstreamResponseDTO();
        downstreamResponseDTO_1.setFirstName("jack");
        downstreamResponseDTO_1.setLastName("attack");
        downstreamResponseDTO_1.setDeepesetFear("spiders");
        downstreamResponseDTO_1.setSsn("123-45-6789");

        DownstreamResponseDTO downstreamResponseDTO_2 = new DownstreamResponseDTO();
        downstreamResponseDTO_2.setFirstName("karen");
        downstreamResponseDTO_2.setLastName("cool");
        downstreamResponseDTO_2.setDeepesetFear("snakes");
        downstreamResponseDTO_2.setSsn("000-00-0000");

        Mockito.when(myServiceMock.getAllPeople())
                .thenReturn(Flux.just(downstreamResponseDTO_1, downstreamResponseDTO_2));

        StepVerifier.create(myController.getPersons())
                .expectNextMatches(personDTO -> personDTO.getLastName().equals(downstreamResponseDTO_1.getLastName())
                        &amp;&amp; personDTO.getFirstName().equals(downstreamResponseDTO_1.getFirstName()))
                .expectNextMatches(personDTO -> personDTO.getLastName().equals(downstreamResponseDTO_2.getLastName())
                        &amp;&amp; personDTO.getFirstName().equals(downstreamResponseDTO_2.getFirstName()))
                .verifyComplete();
    }
}

```

The key parts we are looking at are towards the end of **verifyTransformsCorrectly**, where we first say that "any call to **myServiceMock.getAllPeople()** will respond with
a **Flux** of **DownstreamResponseDTO** s." By putting it into the step verifier, it will handle subscribing for us and ensuring that each item gets pulled through appropriately.
We finally assert that the first and last name of the mocked out objects are indeed mapped to the correct fields on the **PersonDTO**.

That basic structure should handle 80% of your unit testing needs in webflux. If you want to run these tests you can simply:

```bash
mvn clean install

```

As a reminder, feel free to check out the [source code for this post on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/mocking-and-unit-testing).

**Important Update**: There is a follow up article on how to [ensure that your reactor Publisher is actually getting subscribed to](https://nickolasfisher.com/blog/How-to-Unit-Test-that-a-Reactor-Mono-was-Actually-Subscribed-to), rather than just the method that returns the mono being called, which I would recommend anyone new to testing in reactor read and understand.
