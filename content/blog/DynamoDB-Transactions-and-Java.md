---
title: "DynamoDB Transactions and Java"
date: 2020-11-28T20:57:47
draft: false
tags: [java, reactive, aws, dynamodb]
---

DynamoDB transactions can be used for _atomic_ updates. Atomic updates in DynamoDB without transactions can be difficult to implement--you'll often have to manage the current state of the update yourself in something like a saga, and have business logic specific rollback procedures. Further, without a transaction manager, the data will be in an inconsistent state at some point in time while the saga is ongoing. An alternative to that is a Two Phase Commit, but that's also expensive both from the standpoint of developers making it work as well as performance \[2PC typically call for a lock being held during the operation, and even then there's a possibility that the operation ends up in an inconsistent state at some point\].

It is a claim made by AWS that transactions in DynamoDB are ACID--on this point, I'm quite skeptical. But even without full ACID compliance, just having eventual consistency managed outside the application can be extremely helpful. In this article, we will demonstrate how to interact with this feature.

## The Code

The [source code for what follows can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L767). I will leverage work done in previous articles demonstrating how to set up an embedded DynamoDB instance for integration testing, as well as some helper methods. Let's start by creating our table and inserting some sample data:

```java
    @Test
    public void transactions() throws Exception {
        String currentTableName = "TransactionsTest";
        createTableAndWaitForComplete(currentTableName);

        String partitionKey = "Google";
        String rangeKey1 = "Pixel 1";
        String rangeKey2 = "Future Phone";

        // create three items
        Map<String, AttributeValue> pixel1ItemAttributes = getMapWith(partitionKey, rangeKey1);
        pixel1ItemAttributes.put(COLOR, s("Blue"));
        pixel1ItemAttributes.put(YEAR, AttributeValue.builder().n("2012").build());
        putItem(currentTableName, pixel1ItemAttributes);

        Map<String, AttributeValue> futurePhoneAttributes = getMapWith(partitionKey, rangeKey2);
        futurePhoneAttributes.put(COLOR, s("Silver"));
        futurePhoneAttributes.put(YEAR, AttributeValue.builder().n("2030").build());
        putItem(currentTableName, futurePhoneAttributes);

```

This code sets up a DynamoDB table with a hash key that is "Company" and a range key that is "Model". The table name is "TransactionsTest". We then insert two items, "Pixel 1" and "Future Phone", and each item has two additional attributes which should be pretty straightforward.

Now, we can demonstrate an example transaction. Let's start by updating "Pixel 1" to have a "Color" of "Red"--but only if the Color is currently "Blue". If the color is not blue, this operation will fail:

```java

        Map<String, AttributeValue> rangeKey1Map = Map.of(
            COMPANY, s(partitionKey),
            MODEL, s(rangeKey1)
        );

        TransactWriteItem updateColorToRedOnlyIfColorIsAlreadyBlue = TransactWriteItem.builder().update(
            Update.builder()
                .conditionExpression(COLOR + " = :color")
                .expressionAttributeValues(
                    Map.of(
                        ":color", s("Blue"),
                        ":newcolor", s("Red")
                    )
                )
                .tableName(currentTableName)
                .key(
                    rangeKey1Map
                )
                .updateExpression("SET " + COLOR + " = :newcolor")
                .build()
        ).build();

        TransactWriteItemsRequest updateColorOfItem1ToRedTransaction = TransactWriteItemsRequest.builder()
            .transactItems(
                updateColorToRedOnlyIfColorIsAlreadyBlue
            )
            .build();

        dynamoDbAsyncClient.transactWriteItems(updateColorOfItem1ToRedTransaction).get();

        CompletableFuture<GetItemResponse> getRangeKey1Future = dynamoDbAsyncClient.getItem(
            GetItemRequest.builder().key(rangeKey1Map).tableName(currentTableName).build()
        );

        StepVerifier.create(Mono.fromFuture(getRangeKey1Future))
                .expectNextMatches(getItemResponse -> getItemResponse.item().get(COLOR).s().equals("Red"))
                .verifyComplete();

```

After executing the update in a **TransactWriteItemsRequest**, we then verify with a **GetItemRequest** that our change was made--the color at this point is "Red".

That isn't really too interesting at this point. If everything in a "transaction" were guaranteed to succeed, we might as well use a **BatchWriteItemRequest**. It gets more useful when we demonstrate a partial failure. Let's now change two things at once, where because of a condition check failure on one of the items, the entire operation should fail:

```java

        Map<String, AttributeValue> rangeKey2Map = Map.of(
            COMPANY, s(partitionKey),
            MODEL, s(rangeKey2)
        );

        TransactWriteItem updateRangeKey2ColorToOrange = TransactWriteItem.builder().update(
            Update.builder()
                .expressionAttributeValues(
                    Map.of(
                        ":newcolor", s("Orange")
                    )
                )
                .tableName(currentTableName)
                .key(
                    rangeKey1Map
                )
                .updateExpression("SET " + COLOR + " = :newcolor")
                .build()
        ).build();

        TransactWriteItemsRequest multiObjectTransactionThatShouldFailEverything = TransactWriteItemsRequest.builder()
            .transactItems(
                updateColorToRedOnlyIfColorIsAlreadyBlue,
                updateRangeKey2ColorToOrange
            )
            .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.transactWriteItems(multiObjectTransactionThatShouldFailEverything)))
                .expectErrorMatches(throwable -> {
                    List<CancellationReason> cancellationReasons =
                            ((TransactionCanceledException) throwable).cancellationReasons();
                    return cancellationReasons.get(0).code().equals("ConditionalCheckFailed");
                })
                .verify();

```

We are here reusing the **updateColorToRedOnlyIfColorIsAlreadyBlue** transact write item, which we know will fail because the color is already Red, and then collecting it with the **updateRangeKey2ColorToOrange** transact write item. After submitting both as a group, we verify that the response was cancelled with an exception--the reason given is that a condition check failed.

So far so good. Let's now get "Future Phone" out of dynamo and verify that the color is NOT orange--it should have stayed silver because it was submitted as a transaction:

```java
        CompletableFuture<GetItemResponse> getRangeKey2Future = dynamoDbAsyncClient.getItem(
            GetItemRequest.builder().key(rangeKey2Map).tableName(currentTableName).build()
        );

        // one operation (Blue -> Red) failed because of a condition check, therefore ALL operations fail
        StepVerifier.create(Mono.fromFuture(getRangeKey2Future))
            .expectNextMatches(getItemResponse ->
                !getItemResponse.item().get(COLOR).s().equals("Orange")
                    &amp;&amp; getItemResponse.item().get(COLOR).s().equals("Silver")
            )
            .verifyComplete();
    }

```

And this also passes! Be sure to [check out the source code for this article on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L767).
