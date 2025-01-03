---
title: "DynamoDB Transactions and Java"
date: 2020-11-28T20:57:47
draft: false
---

DynamoDB transactions can be used for _atomic_ updates. Atomic updates in DynamoDB without transactions can be difficult to implement--you&#39;ll often have to manage the current state of the update yourself in something like a saga, and have business logic specific rollback procedures. Further, without a transaction manager, the data will be in an inconsistent state at some point in time while the saga is ongoing. An alternative to that is a Two Phase Commit, but that&#39;s also expensive both from the standpoint of developers making it work as well as performance \[2PC typically call for a lock being held during the operation, and even then there&#39;s a possibility that the operation ends up in an inconsistent state at some point\].

It is a claim made by AWS that transactions in DynamoDB are ACID--on this point, I&#39;m quite skeptical. But even without full ACID compliance, just having eventual consistency managed outside the application can be extremely helpful. In this article, we will demonstrate how to interact with this feature.

## The Code

The [source code for what follows can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L767). I will leverage work done in previous articles demonstrating how to set up an embedded DynamoDB instance for integration testing, as well as some helper methods. Let&#39;s start by creating our table and inserting some sample data:

```java
    @Test
    public void transactions() throws Exception {
        String currentTableName = &#34;TransactionsTest&#34;;
        createTableAndWaitForComplete(currentTableName);

        String partitionKey = &#34;Google&#34;;
        String rangeKey1 = &#34;Pixel 1&#34;;
        String rangeKey2 = &#34;Future Phone&#34;;

        // create three items
        Map&lt;String, AttributeValue&gt; pixel1ItemAttributes = getMapWith(partitionKey, rangeKey1);
        pixel1ItemAttributes.put(COLOR, s(&#34;Blue&#34;));
        pixel1ItemAttributes.put(YEAR, AttributeValue.builder().n(&#34;2012&#34;).build());
        putItem(currentTableName, pixel1ItemAttributes);

        Map&lt;String, AttributeValue&gt; futurePhoneAttributes = getMapWith(partitionKey, rangeKey2);
        futurePhoneAttributes.put(COLOR, s(&#34;Silver&#34;));
        futurePhoneAttributes.put(YEAR, AttributeValue.builder().n(&#34;2030&#34;).build());
        putItem(currentTableName, futurePhoneAttributes);

```

This code sets up a DynamoDB table with a hash key that is &#34;Company&#34; and a range key that is &#34;Model&#34;. The table name is &#34;TransactionsTest&#34;. We then insert two items, &#34;Pixel 1&#34; and &#34;Future Phone&#34;, and each item has two additional attributes which should be pretty straightforward.

Now, we can demonstrate an example transaction. Let&#39;s start by updating &#34;Pixel 1&#34; to have a &#34;Color&#34; of &#34;Red&#34;--but only if the Color is currently &#34;Blue&#34;. If the color is not blue, this operation will fail:

```java

        Map&lt;String, AttributeValue&gt; rangeKey1Map = Map.of(
            COMPANY, s(partitionKey),
            MODEL, s(rangeKey1)
        );

        TransactWriteItem updateColorToRedOnlyIfColorIsAlreadyBlue = TransactWriteItem.builder().update(
            Update.builder()
                .conditionExpression(COLOR &#43; &#34; = :color&#34;)
                .expressionAttributeValues(
                    Map.of(
                        &#34;:color&#34;, s(&#34;Blue&#34;),
                        &#34;:newcolor&#34;, s(&#34;Red&#34;)
                    )
                )
                .tableName(currentTableName)
                .key(
                    rangeKey1Map
                )
                .updateExpression(&#34;SET &#34; &#43; COLOR &#43; &#34; = :newcolor&#34;)
                .build()
        ).build();

        TransactWriteItemsRequest updateColorOfItem1ToRedTransaction = TransactWriteItemsRequest.builder()
            .transactItems(
                updateColorToRedOnlyIfColorIsAlreadyBlue
            )
            .build();

        dynamoDbAsyncClient.transactWriteItems(updateColorOfItem1ToRedTransaction).get();

        CompletableFuture&lt;GetItemResponse&gt; getRangeKey1Future = dynamoDbAsyncClient.getItem(
            GetItemRequest.builder().key(rangeKey1Map).tableName(currentTableName).build()
        );

        StepVerifier.create(Mono.fromFuture(getRangeKey1Future))
                .expectNextMatches(getItemResponse -&gt; getItemResponse.item().get(COLOR).s().equals(&#34;Red&#34;))
                .verifyComplete();

```

After executing the update in a **TransactWriteItemsRequest**, we then verify with a **GetItemRequest** that our change was made--the color at this point is &#34;Red&#34;.

That isn&#39;t really too interesting at this point. If everything in a &#34;transaction&#34; were guaranteed to succeed, we might as well use a **BatchWriteItemRequest**. It gets more useful when we demonstrate a partial failure. Let&#39;s now change two things at once, where because of a condition check failure on one of the items, the entire operation should fail:

```java

        Map&lt;String, AttributeValue&gt; rangeKey2Map = Map.of(
            COMPANY, s(partitionKey),
            MODEL, s(rangeKey2)
        );

        TransactWriteItem updateRangeKey2ColorToOrange = TransactWriteItem.builder().update(
            Update.builder()
                .expressionAttributeValues(
                    Map.of(
                        &#34;:newcolor&#34;, s(&#34;Orange&#34;)
                    )
                )
                .tableName(currentTableName)
                .key(
                    rangeKey1Map
                )
                .updateExpression(&#34;SET &#34; &#43; COLOR &#43; &#34; = :newcolor&#34;)
                .build()
        ).build();

        TransactWriteItemsRequest multiObjectTransactionThatShouldFailEverything = TransactWriteItemsRequest.builder()
            .transactItems(
                updateColorToRedOnlyIfColorIsAlreadyBlue,
                updateRangeKey2ColorToOrange
            )
            .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.transactWriteItems(multiObjectTransactionThatShouldFailEverything)))
                .expectErrorMatches(throwable -&gt; {
                    List&lt;CancellationReason&gt; cancellationReasons =
                            ((TransactionCanceledException) throwable).cancellationReasons();
                    return cancellationReasons.get(0).code().equals(&#34;ConditionalCheckFailed&#34;);
                })
                .verify();

```

We are here reusing the **updateColorToRedOnlyIfColorIsAlreadyBlue** transact write item, which we know will fail because the color is already Red, and then collecting it with the **updateRangeKey2ColorToOrange** transact write item. After submitting both as a group, we verify that the response was cancelled with an exception--the reason given is that a condition check failed.

So far so good. Let&#39;s now get &#34;Future Phone&#34; out of dynamo and verify that the color is NOT orange--it should have stayed silver because it was submitted as a transaction:

```java
        CompletableFuture&lt;GetItemResponse&gt; getRangeKey2Future = dynamoDbAsyncClient.getItem(
            GetItemRequest.builder().key(rangeKey2Map).tableName(currentTableName).build()
        );

        // one operation (Blue -&gt; Red) failed because of a condition check, therefore ALL operations fail
        StepVerifier.create(Mono.fromFuture(getRangeKey2Future))
            .expectNextMatches(getItemResponse -&gt;
                !getItemResponse.item().get(COLOR).s().equals(&#34;Orange&#34;)
                    &amp;&amp; getItemResponse.item().get(COLOR).s().equals(&#34;Silver&#34;)
            )
            .verifyComplete();
    }

```

And this also passes! Be sure to [check out the source code for this article on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L767).
