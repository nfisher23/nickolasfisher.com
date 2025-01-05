---
title: "DynamoDB and Duplicate Keys in Global Secondary Indexes"
date: 2020-11-01T23:27:39
draft: false
tags: [java, aws, dynamodb, webflux]
---

If there's something in the documentation about what the behavior of a DynamoDB Global Secondary Index is when there are duplicate keys in the index, it isn't easy to find. I tested this empirically with an embedded DynamoDB mock for java and will quickly share my findings here with you.

The [source code for this post can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L565).

## TL;DR

If there are duplicate keys, they _do not overwrite each other_. They are both present in the index. What that means in practice is that you issue a query against the index, and response payload will just include all the elements associated with that key.

## Actual Example Demonstrating It

The [boilerplate code for setting up an embedded DynamoDB instance for java integration testing](https://nickolasfisher.com/blog/configuring-an-in-memory-dynamodb-instance-with-java-for-integration-testing) was covered in a previous post and I won't belabor that here. I'll just jump into the test case.

First, we have to set up our table to work with. This table will have:

- A composite primary key, where the partition key is "Company" \[of type string\] and "Model" \[also of type string\]
- A table name of "DuplicateKeysTest"
- A global secondary index \[called "YearIndex"\] that has a simple primary key of "Year" \[of type number\]

Here's the code, because it's java using the builder pattern, it's pretty verbose:

```java
    @Test
    public void gsiDuplicateKeysExample() throws Exception {
        String currentTableName = "DuplicateKeysTest";
        String YEAR_GSI_NAME = "YearIndex";

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

```

Now we'll populate some test data. We'll put three items in our table, all with the same hash attribute of "Google", all with different range attributes, as well as two of them with a year attribute of "2012".

```java

        String partitionKey = "Google";
        String rangeKey1 = "Pixel 1";
        String rangeKey2 = "Future Phone";
        String rangeKey3 = "Pixel 2";

        // create three items
        Map<String, AttributeValue> pixel1ItemAttributes = getMapWith(partitionKey, rangeKey1);
        pixel1ItemAttributes.put(COLOR, AttributeValue.builder().s("Blue").build());
        pixel1ItemAttributes.put(YEAR, AttributeValue.builder().n("2012").build());
        putItem(currentTableName, pixel1ItemAttributes);

        Map<String, AttributeValue> futurePhoneAttributes = getMapWith(partitionKey, rangeKey2);
        futurePhoneAttributes.put(COLOR, AttributeValue.builder().s("Silver").build());
        futurePhoneAttributes.put(YEAR, AttributeValue.builder().n("2012").build());
        putItem(currentTableName, futurePhoneAttributes);

        Map<String, AttributeValue> pixel2ItemAttributes = getMapWith(partitionKey, rangeKey3);
        pixel2ItemAttributes.put(COLOR, AttributeValue.builder().s("Cyan").build());
        pixel2ItemAttributes.put(YEAR, AttributeValue.builder().n("2014").build());
        putItem(currentTableName, pixel2ItemAttributes);

```

So now one of two things will happen, depending on the behavior of DynamoDB when it encounters duplicate primary keys in a global secondary index. Either it will overwrite the existing record or it will place them next to each other and allow us to get all the results that happen to share the same primary key.

It turns out that it does not overwrite on indexes \[as it does on the base table\] and instead allows you to get all the items with the same key. Here's the assertion that proves it:

```java

        Thread.sleep(1000); // GSI's are eventually consistent

        Condition equals2012Condition = Condition.builder()
                .comparisonOperator(ComparisonOperator.EQ)
                .attributeValueList(
                    AttributeValue.builder()
                            .n("2012")
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
                .expectNextMatches(queryResponse ->
                    queryResponse.count() == 2
                        &amp;&amp; queryResponse.items().stream().anyMatch(m -> m.get(COLOR).s().equals("Blue"))
                        &amp;&amp; queryResponse.items().stream().anyMatch(m -> m.get(COLOR).s().equals("Silver"))
                )
                .verifyComplete();

```

We verify that there are two items with the same hash key, then verify that they are unique by checking the "Color" attribute on those items

You should be able to clone the source repository and run this test, it will pass. Remember you can [check out the source code on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L565) and play around with this yourself.
