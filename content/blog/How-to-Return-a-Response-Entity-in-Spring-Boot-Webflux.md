---
title: "How to Return a Response Entity in Spring Boot Webflux"
date: 2020-07-19T16:07:33
draft: false
---

In my last post on [getting started with spring boot webflux and AWS DynamoDB](https://nickolasfisher.com/blog/DynamoDB-and-Spring-Boot-Webflux-A-Working-Introduction), I mentioned that it wasn&#39;t immediately obvious to find a way to customize the response code in a spring boot **RestController**, so I opted to use handlers instead.

It turns out it was pretty simple. This handler code from that post:

```java
    public Mono&lt;ServerResponse&gt; getSinglePhoneHandler(ServerRequest serverRequest) {
        String companyName = serverRequest.pathVariable(&#34;company-name&#34;);
        String modelName = serverRequest.pathVariable(&#34;model-name&#34;);

        Map&lt;String, AttributeValue&gt; getSinglePhoneItemRequest = new HashMap&lt;&gt;();
        getSinglePhoneItemRequest.put(COMPANY, AttributeValue.builder().s(companyName).build());
        getSinglePhoneItemRequest.put(MODEL, AttributeValue.builder().s(modelName).build());
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(PHONES_TABLENAME)
                .key(getSinglePhoneItemRequest)
                .build();

        CompletableFuture&lt;GetItemResponse&gt; item = dynamoDbAsyncClient.getItem(getItemRequest);
        return Mono.fromCompletionStage(item)
                .flatMap(getItemResponse -&gt; {
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

    public static final String PHONES_TABLENAME = &#34;Phones&#34;;
    public static final String COMPANY = &#34;Company&#34;;
    public static final String MODEL = &#34;Model&#34;;
    private final DynamoDbAsyncClient dynamoDbAsyncClient;

    public DynamoController(DynamoDbAsyncClient dynamoDbAsyncClient) {
        this.dynamoDbAsyncClient = dynamoDbAsyncClient;
    }

    @GetMapping(&#34;/company/{company-name}/model/{model-name}/phone&#34;)
    public Mono&lt;ResponseEntity&lt;Phone&gt;&gt; getPhone(@PathVariable(&#34;company-name&#34;) String companyName,
                                @PathVariable(&#34;model-name&#34;) String modelName) {
        Map&lt;String, AttributeValue&gt; getSinglePhoneItemRequest = new HashMap&lt;&gt;();
        getSinglePhoneItemRequest.put(COMPANY, AttributeValue.builder().s(companyName).build());
        getSinglePhoneItemRequest.put(MODEL, AttributeValue.builder().s(modelName).build());
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(PHONES_TABLENAME)
                .key(getSinglePhoneItemRequest)
                .build();

        CompletableFuture&lt;GetItemResponse&gt; item = dynamoDbAsyncClient.getItem(getItemRequest);
        return Mono.fromCompletionStage(item)
                .map(getItemResponse -&gt; {
                    if (!getItemResponse.hasItem()) {
                        return ResponseEntity.status(HttpStatus.NOT_FOUND).&lt;Phone&gt;body(null);
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
