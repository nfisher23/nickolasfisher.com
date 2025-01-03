---
title: "Atomic Incrementing in DynamoDB with the Java AWS SDK 2.0"
date: 2021-03-01T00:00:00
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo).

When you update an item in DynamoDB, you can optionally update the item in place. That is, instead of **read-increment-write**, you can just issue a command that says **increment this value in place**. This behavior is detailed in the [AWS documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/WorkingWithItems.html#WorkingWithItems.AtomicCounters), and I will provide an example for how to do so with the Java AWS SDK 2.0, which has full reactive support.

We will start by building off work done on a previous post where we [set up an embedded DynamoDB instance and integrated it with the AWS SDK 2.0](https://nickolasfisher.com/blog/Configuring-an-In-Memory-DynamoDB-instance-with-Java-for-Integration-Testing). With that in place, we can create a test table and add an item to work with \[we obviously will need an item to increment in order to prove this out\]:

``` java
    @Test
    public void atomicCounting() throws Exception {
        String currentTableName = &#34;PhonesAtomicCounting&#34;;

        createTableAndWaitForComplete(currentTableName);

        String stubCompanyName = &#34;Nokia&#34;;
        String stubPhoneName = &#34;flip-phone-1&#34;;

        Map&lt;String, AttributeValue&gt; itemAttributes = getMapWith(stubCompanyName, stubPhoneName);
        itemAttributes.put(&#34;Color&#34;, AttributeValue.builder().s(&#34;Orange&#34;).build());
        itemAttributes.put(&#34;Version&#34;, AttributeValue.builder().n(Long.valueOf(1L).toString()).build());
        itemAttributes.put(&#34;NumberSold&#34;, AttributeValue.builder().n(Long.valueOf(1L).toString()).build());

        PutItemRequest populateDataItemRequest = PutItemRequest.builder()
                .tableName(currentTableName)
                .item(itemAttributes)
                .build();

        // populate initial data
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(populateDataItemRequest)))
                .expectNextCount(1)
                .verifyComplete();

```

We create a partition and sort key on a table called **PhonesAtomicCounting**. This table stores phones, so we put a phone in there where the company that creates the phone is named &#34;Nokia&#34; and the phone name is &#34;flip-phone-1&#34;. Other item attributes include &#34;Color&#34;, &#34;Version&#34;, and &#34;NumberSold&#34;.

Now let&#39;s say that we want to blindly increment **NumberSold**, and we&#39;re okay with the consequences/caveat that it&#39;s not idempotent \[it will increment every time it&#39;s called, if you want idempotency you will want to look into Optimistic Locking\]. If that&#39;s our game, this is how it can be done:

``` java
        UpdateItemRequest updateItemRequest = UpdateItemRequest.builder()
                .tableName(currentTableName)
                .key(getMapWith(stubCompanyName, stubPhoneName))
                .updateExpression(&#34;SET Version = Version &#43; :incr_amt, NumberSold = NumberSold &#43; :num_sold_incr_amt&#34;)
                .expressionAttributeValues(Map.of(
                        &#34;:incr_amt&#34;,
                        AttributeValue.builder().n(&#34;1&#34;).build(),
                        &#34;:num_sold_incr_amt&#34;,
                        AttributeValue.builder().n(&#34;2&#34;).build()
                    )
                )
                .build();

        StepVerifier.create(Mono.fromFuture(() -&gt; dynamoDbAsyncClient.updateItem(updateItemRequest)))
                .expectNextMatches(updateItemResponse -&gt; {
                    return true;
                }).verifyComplete();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder()
                        .tableName(currentTableName)
                        .key(getMapWith(stubCompanyName, stubPhoneName))
                        .build())
            ))
            .expectNextMatches(getItemResponse -&gt; getItemResponse.item().get(&#34;NumberSold&#34;).n().equals(&#34;3&#34;))
            .verifyComplete();

    }

```

Here, we update the item we created previously by incrementing **Version** by 1 and **NumberSold** by 2. We then verify that our changes applied by getting the item out of the table and verifying that the **NumberSold** did indeed increment by two.


