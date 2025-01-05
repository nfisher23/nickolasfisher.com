---
title: "How to Return a Response Entity in Spring Boot Webflux"
date: 2020-07-19T16:07:33
draft: false
tags: [java, spring, reactive, aws, dynamodb, webflux]
---

In my last post on [getting started with spring boot webflux and AWS DynamoDB](https://nickolasfisher.com/blog/dynamodb-and-spring-boot-webflux-a-working-introduction), I mentioned that it wasn't immediately obvious to find a way to customize the response code in a spring boot **RestController**, so I opted to use handlers instead.

It turns out it was pretty simple. This handler code from that post:

```java
    public Mono<ServerResponse> getSinglePhoneHandler(ServerRequest serverRequest) {
        String companyName = serverRequest.pathVariable("company-name");
        String modelName = serverRequest.pathVariable("model-name");

        Map<String, AttributeValue> getSinglePhoneItemRequest = new HashMap<>();
        getSinglePhoneItemRequest.put(COMPANY, AttributeValue.builder().s(companyName).build());
        getSinglePhoneItemRequest.put(MODEL, AttributeValue.builder().s(modelName).build());
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(PHONES_TABLENAME)
                .key(getSinglePhoneItemRequest)
                .build();

        CompletableFuture<GetItemResponse> item = dynamoDbAsyncClient.getItem(getItemRequest);
        return Mono.fromCompletionStage(item)
                .flatMap(getItemResponse -> {
                    if (!getItemResponse.hasItem()) {
                        return ServerResponse.notFound().build();
                    }
                    Phone phone = new Phone();
                    phone.setColors(getItemResponse.item().get(COLORS).ss());
                    phone.setCompany(getItemResponse.item().get(COMPANY).s());
                    String stringSize = getItemResponse.item().get(SIZE).n();
                    phone.setSize(stringSize == null ? null : Integer.valueOf(stringSize));
                    phone.setModel(getItemResponse.item().get(MODEL).s());
                    return ServerResponse.ok()
                            .contentType(MediaType.APPLICATION_JSON)
                            .body(BodyInserters.fromValue(phone));
                });

```

Can be refactored into this:

```java
@RestController
public class DynamoController {

    public static final String PHONES_TABLENAME = "Phones";
    public static final String COMPANY = "Company";
    public static final String MODEL = "Model";
    private final DynamoDbAsyncClient dynamoDbAsyncClient;

    public DynamoController(DynamoDbAsyncClient dynamoDbAsyncClient) {
        this.dynamoDbAsyncClient = dynamoDbAsyncClient;
    }

    @GetMapping("/company/{company-name}/model/{model-name}/phone")
    public Mono<ResponseEntity<Phone>> getPhone(@PathVariable("company-name") String companyName,
                                @PathVariable("model-name") String modelName) {
        Map<String, AttributeValue> getSinglePhoneItemRequest = new HashMap<>();
        getSinglePhoneItemRequest.put(COMPANY, AttributeValue.builder().s(companyName).build());
        getSinglePhoneItemRequest.put(MODEL, AttributeValue.builder().s(modelName).build());
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(PHONES_TABLENAME)
                .key(getSinglePhoneItemRequest)
                .build();

        CompletableFuture<GetItemResponse> item = dynamoDbAsyncClient.getItem(getItemRequest);
        return Mono.fromCompletionStage(item)
                .map(getItemResponse -> {
                    if (!getItemResponse.hasItem()) {
                        return ResponseEntity.status(HttpStatus.NOT_FOUND).<Phone>body(null);
                    }
                    Phone phone = new Phone();
                    phone.setColors(getItemResponse.item().get(COLORS).ss());
                    phone.setCompany(getItemResponse.item().get(COMPANY).s());
                    String stringSize = getItemResponse.item().get(SIZE).n();
                    phone.setSize(stringSize == null ? null : Integer.valueOf(stringSize));
                    phone.setModel(getItemResponse.item().get(MODEL).s());
                    return ResponseEntity.ok(phone);
                });
    }
}

```

The important part that can be easy to miss in that we are using **map** rather than **flatMap**.
