---
title: "How to Make Parallel API calls in Spring Boot Webflux"
date: 2020-09-19T16:03:01
draft: false
tags: [java, spring, reactive, webflux]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/api-calls-and-resilience).

Following up on the last post, which was making sequential calls to downstream services, sometimes you are in a position where you can make calls in parallel and merge the results. In this case, we want to use **zip**.

Let's take the framework we started in the last post and demonstrate how this might work.

### DTOs

Recall we had two simple DTOs:

```java
public class FirstCallDTO {
    private Integer fieldFromFirstCall;

    public Integer getFieldFromFirstCall() {
        return fieldFromFirstCall;
    }

    public void setFieldFromFirstCall(Integer fieldFromFirstCall) {
        this.fieldFromFirstCall = fieldFromFirstCall;
    }
}

...another file...

public class SecondCallDTO {
    private String fieldFromSecondCall;

    public String getFieldFromSecondCall() {
        return fieldFromSecondCall;
    }

    public void setFieldFromSecondCall(String fieldFromSecondCall) {
        this.fieldFromSecondCall = fieldFromSecondCall;
    }
}

```

Let's now add a DTO that will serve to merge the results of the these two DTOs:

```java
public class MergedCallsDTO {
    private Integer fieldOne;
    private String fieldTwo;

    public Integer getFieldOne() {
        return fieldOne;
    }

    public void setFieldOne(Integer fieldOne) {
        this.fieldOne = fieldOne;
    }

    public String getFieldTwo() {
        return fieldTwo;
    }

    public void setFieldTwo(String fieldTwo) {
        this.fieldTwo = fieldTwo;
    }
}

```

With that in place, let's follow TDD and set up a bare bones method in our **CombiningCallsService**:

```java
    public Mono<MergedCallsDTO> mergedCalls(Integer firstEndpointParam, Integer secondEndpointParam) {
        return null;
    }

```

Our test should:

- Declare expectations on mock server for two endpoints
- Ensure the response matches the contract of the first two DTOs
- Make assertions on the merged result

That test, using mock server, can look like this:

```java
    @Test
    public void mergedCalls_callsBothEndpointsAndMergesResults() {
        HttpRequest expectedFirstRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath("/first/endpoint/25");

        this.clientAndServer.when(
                expectedFirstRequest
        ).respond(
                HttpResponse.response()
                        .withBody("{\"fieldFromFirstCall\": 250}")
                        .withContentType(MediaType.APPLICATION_JSON)
        );

        HttpRequest expectedSecondRequest = HttpRequest.request()
                .withMethod(HttpMethod.GET.name())
                .withPath("/second/endpoint/45");

        this.clientAndServer.when(
                expectedSecondRequest
        ).respond(
                HttpResponse.response()
                        .withBody("{\"fieldFromSecondCall\": \"something\"}")
                        .withContentType(MediaType.APPLICATION_JSON)
        );

        StepVerifier.create(this.combiningCallsService.mergedCalls(25, 45))
                .expectNextMatches(mergedCallsDTO -> 250 == mergedCallsDTO.getFieldOne()
                        &amp;&amp; "something".equals(mergedCallsDTO.getFieldTwo())
                )
                .verifyComplete();

        this.clientAndServer.verify(expectedFirstRequest, VerificationTimes.once());
        this.clientAndServer.verify(expectedSecondRequest, VerificationTimes.once());
    }

```

While pretty self explanatory, we are using the reactor test's **StepVerifier** to verify that the mono, upon completing and calling back, will return an object that matches the assertion in the **expectNextMatches** block.

You will, predictably, see this test fail without any code to make it pass, so let's write that code now:

```java
    public Mono<MergedCallsDTO> mergedCalls(Integer firstEndpointParam, Integer secondEndpointParam) {
        Mono<FirstCallDTO> firstCallDTOMono = this.serviceAWebClient.get()
                .uri(uriBuilder -> uriBuilder.path("/first/endpoint/{param}").build(firstEndpointParam))
                .retrieve()
                .bodyToMono(FirstCallDTO.class);

        Mono<SecondCallDTO> secondCallDTOMono = this.serviceAWebClient.get()
                .uri(uriBuilder -> uriBuilder.path("/second/endpoint/{param}").build(secondEndpointParam))
                .retrieve()
                .bodyToMono(SecondCallDTO.class);

        // nothing has been subscribed to, those calls above are not waiting for anything and are not subscribed to, yet

        // zipping the monos will invoke the callback in "map" once both of them have completed, merging the results
        // into a tuple.
        return Mono.zip(firstCallDTOMono, secondCallDTOMono)
                .map(objects -> {
                    MergedCallsDTO mergedCallsDTO = new MergedCallsDTO();

                    mergedCallsDTO.setFieldOne(objects.getT1().getFieldFromFirstCall());
                    mergedCallsDTO.setFieldTwo(objects.getT2().getFieldFromSecondCall());

                    return mergedCallsDTO;
                });
    }

```

As you can see in the code comments, simply making a block of code return a **Mono** doesn't actually do anything until it is subscribed to. In the case of our test, we are subscribing directly to it. If we wrote an endpoint that were invoked when someone made an http request to our application, then it would get subscribed to only at the end of the chain and we wouldn't ever actually write **subscribe** anywhere.

So, by using **zip**, they are both kicked off at the same time, and we wait for both of them to complete, merging the results with **map**. If you run the test, it will now pass.
