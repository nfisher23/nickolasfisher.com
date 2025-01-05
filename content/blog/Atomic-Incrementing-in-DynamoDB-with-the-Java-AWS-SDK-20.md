---
title: "Atomic Incrementing in DynamoDB with the Java AWS SDK 2.0"
date: 2021-03-28T02:00:30
draft: false
tags: [java, reactive, dynamodb]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo).

When you update an item in DynamoDB, you can optionally update the item in place. That is, instead of **read-increment-write**, you can just issue a command that says **increment this value in place**. This behavior is detailed in the [AWS documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/WorkingWithItems.html#WorkingWithItems.AtomicCounters), and I will provide an example for how to do so with the Java AWS SDK 2.0, which has full reactive support.

We will start by building off work done on a previous post where we [set up an embedded DynamoDB instance and integrated it with the AWS SDK 2.0](https://nickolasfisher.com/blog/configuring-an-in-memory-dynamodb-instance-with-java-for-integration-testing). With that in place, we can create a test table and add an item to work with \[we obviously will need an item to increment in order to prove this out\]:

```java
    @Test
    public void atomicCounting() throws Exception {
        String currentTableName = "PhonesAtomicCounting";

        createTableAndWaitForComplete(currentTableName);

        String stubCompanyName = "Nokia";
        String stubPhoneName = "flip-phone-1";

        Map<String, AttributeValue> itemAttributes = getMapWith(stubCompanyName, stubPhoneName);
        itemAttributes.put("Color", AttributeValue.builder().s("Orange").build());
        itemAttributes.put("Version", AttributeValue.builder().n(Long.valueOf(1L).toString()).build());
        itemAttributes.put("NumberSold", AttributeValue.builder().n(Long.valueOf(1L).toString()).build());

        PutItemRequest populateDataItemRequest = PutItemRequest.builder()
                .tableName(currentTableName)
                .item(itemAttributes)
                .build();

        // populate initial data
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(populateDataItemRequest)))
                .expectNextCount(1)
                .verifyComplete();

```

We create a partition and sort key on a table called **PhonesAtomicCounting**. This table stores phones, so we put a phone in there where the company that creates the phone is named "Nokia" and the phone name is "flip-phone-1". Other item attributes include "Color", "Version", and "NumberSold".

Now let's say that we want to blindly increment **NumberSold**, and we're okay with the consequences/caveat that it's not idempotent \[it will increment every time it's called, if you want idempotency you will want to look into Optimistic Locking\]. If that's our game, this is how it can be done:

```java
        UpdateItemRequest updateItemRequest = UpdateItemRequest.builder()
                .tableName(currentTableName)
                .key(getMapWith(stubCompanyName, stubPhoneName))
                .updateExpression("SET Version = Version + :incr_amt, NumberSold = NumberSold + :num_sold_incr_amt")
                .expressionAttributeValues(Map.of(
                        ":incr_amt",
                        AttributeValue.builder().n("1").build(),
                        ":num_sold_incr_amt",
                        AttributeValue.builder().n("2").build()
                    )
                )
                .build();

        StepVerifier.create(Mono.fromFuture(() -> dynamoDbAsyncClient.updateItem(updateItemRequest)))
                .expectNextMatches(updateItemResponse -> {
                    return true;
                }).verifyComplete();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder()
                        .tableName(currentTableName)
                        .key(getMapWith(stubCompanyName, stubPhoneName))
                        .build())
            ))
            .expectNextMatches(getItemResponse -> getItemResponse.item().get("NumberSold").n().equals("3"))
            .verifyComplete();

    }

```

Here, we update the item we created previously by incrementing **Version** by 1 and **NumberSold** by 2. We then verify that our changes applied by getting the item out of the table and verifying that the **NumberSold** did indeed increment by two.
