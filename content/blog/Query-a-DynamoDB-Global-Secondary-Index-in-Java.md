---
title: "Query a DynamoDB Global Secondary Index in Java"
date: 2020-11-01T22:40:46
draft: false
---

A [DynamoDB Global Secondary Index](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GSI.html) is an eventually consistent way to efficiently query for data that is not normally found without a table scan. It has [some similarities to Local Secondary Indexes, which we covered in the last post](https://nickolasfisher.com/blog/Query-a-DynamoDB-Local-Secondary-Index-with-Java), but are more flexible than them because they can be created, updated, and deleted after the base table has been created, which is not true of Local Secondary Indexes.

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L456).

This post will walk through some sample code in Java, using the AWS SDK 2.0, with full reactive support.

## Create Table and GSI

I will elect to create both the base table as well as the GSI at the same time for simplicity. Note that, when you&#39;re managing DynamoDB in native AWS \[i.e. not local development\], you should prefer to use something like terraform to manage tables and GSIs.

```java
    @Test
    public void globalSecondaryIndex() throws Exception {
        String currentTableName = &#34;GlobalSecondaryIndexTest&#34;;
        String YEAR_GSI_NAME = &#34;YearModelIndex&#34;;

        ProvisionedThroughput defaultProvisionedThroughput = ProvisionedThroughput.builder()
                .readCapacityUnits(100L)
                .writeCapacityUnits(100L)
                .build();

        dynamoDbAsyncClient.createTable(CreateTableRequest.builder()
                .keySchema(
                    KeySchemaElement.builder()
                            .keyType(KeyType.HASH)
                            .attributeName(COMPANY)
                            .build(),
                    KeySchemaElement.builder()
                            .keyType(KeyType.RANGE)
                            .attributeName(MODEL)
                            .build()
                )
                .attributeDefinitions(
                    AttributeDefinition.builder()
                        .attributeName(COMPANY)
                        .attributeType(ScalarAttributeType.S)
                        .build(),
                    AttributeDefinition.builder()
                        .attributeName(MODEL)
                        .attributeType(ScalarAttributeType.S)
                        .build(),
                    AttributeDefinition.builder()
                        .attributeName(YEAR)
                        .attributeType(ScalarAttributeType.N)
                        .build()
                )
                .provisionedThroughput(defaultProvisionedThroughput)
                .tableName(currentTableName)
                .globalSecondaryIndexes(GlobalSecondaryIndex.builder()
                    .indexName(YEAR_GSI_NAME)
                    .keySchema(
                        KeySchemaElement.builder()
                            .attributeName(YEAR)
                            .keyType(KeyType.HASH)
                            .build(),
                        KeySchemaElement.builder()
                            .attributeName(MODEL)
                            .keyType(KeyType.RANGE)
                            .build()
                    ).projection(
                        Projection.builder()
                            .projectionType(ProjectionType.ALL)
                            .build()
                    )
                    .provisionedThroughput(defaultProvisionedThroughput)
                    .build()
            ).build()
        ).get();
    }

```

This code is verbose for several reasons, but you can see that we&#39;re creating a table with a hash attribute and range attribute, as well as an accompanying global secondary index \[using **GlobalSecondaryIndex.builder** that has a completely different hash attribute \[though the same range attribute\]. We have elected to project all attributes from the base table to the GSI in this case, which is not the default.

Let&#39;s now set up some data to work with in our table:

```java
        String partitionKey = &#34;Google&#34;;
        String rangeKey1 = &#34;Pixel 1&#34;;
        String rangeKey2 = &#34;Future Phone&#34;;
        String rangeKey3 = &#34;Pixel 2&#34;;

        // create three items
        Map&lt;String, AttributeValue&gt; pixel1ItemAttributes = getMapWith(partitionKey, rangeKey1);
        pixel1ItemAttributes.put(COLOR, AttributeValue.builder().s(&#34;Blue&#34;).build());
        pixel1ItemAttributes.put(YEAR, AttributeValue.builder().n(&#34;2012&#34;).build());
        putItem(currentTableName, pixel1ItemAttributes);

        Map&lt;String, AttributeValue&gt; futurePhoneAttributes = getMapWith(partitionKey, rangeKey2);
        futurePhoneAttributes.put(COLOR, AttributeValue.builder().s(&#34;Silver&#34;).build());
        futurePhoneAttributes.put(YEAR, AttributeValue.builder().n(&#34;2030&#34;).build());
        putItem(currentTableName, futurePhoneAttributes);

        Map&lt;String, AttributeValue&gt; pixel2ItemAttributes = getMapWith(partitionKey, rangeKey3);
        pixel2ItemAttributes.put(COLOR, AttributeValue.builder().s(&#34;Cyan&#34;).build());
        pixel2ItemAttributes.put(YEAR, AttributeValue.builder().n(&#34;2014&#34;).build());
        putItem(currentTableName, pixel2ItemAttributes);

```

We&#39;re reusing some code developed in a previous article to put three items in this table, all with the same hash attribute as **Google** and different range attributes.

## Query the GSI

With the table/GSI created and some sample data to work with, we can now query the GSI for data:

```java
        Thread.sleep(1000); // GSI&#39;s are eventually consistent

        Condition equals2012Condition = Condition.builder()
                .comparisonOperator(ComparisonOperator.EQ)
                .attributeValueList(
                    AttributeValue.builder()
                        .n(&#34;2012&#34;)
                        .build()
                )
                .build();

        QueryRequest equals2012Query = QueryRequest.builder()
                .tableName(currentTableName)
                .keyConditions(
                    Map.of(
                        YEAR, equals2012Condition
                    )
                )
                .indexName(YEAR_GSI_NAME)
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.query(equals2012Query)))
                .expectNextMatches(queryResponse -&gt;
                    queryResponse.count() == 1
                        &amp;&amp; queryResponse.items().get(0).get(COLOR).s().equals(&#34;Blue&#34;)
                        &amp;&amp; queryResponse.items().get(0).get(MODEL).s().equals(&#34;Pixel 1&#34;)
                )
                .verifyComplete();

```

The first thing we&#39;ll do is add a small sleep so that our test will consistently pass \[Global Secondary Indexes are eventually consistent\]. We then create a query that gets all items that have the hash attribute of &#34;2012&#34;. We leverage **StepVerifier** and **Mono** to wrap our async call, finally verifying that the query returns the data we expect.

If you run this test locally, you should see it pass. Remember to [check out the source code on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L456).
