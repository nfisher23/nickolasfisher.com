---
title: "DynamoDB and Duplicate Keys in Global Secondary Indexes"
date: 2020-11-01T23:27:39
draft: false
---

If there&#39;s something in the documentation about what the behavior of a DynamoDB Global Secondary Index is when there are duplicate keys in the index, it isn&#39;t easy to find. I tested this empirically with an embedded DynamoDB mock for java and will quickly share my findings here with you.

The [source code for this post can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L565).

## TL;DR

If there are duplicate keys, they _do not overwrite each other_. They are both present in the index. What that means in practice is that you issue a query against the index, and response payload will just include all the elements associated with that key.

## Actual Example Demonstrating It

The [boilerplate code for setting up an embedded DynamoDB instance for java integration testing](https://nickolasfisher.com/blog/Configuring-an-In-Memory-DynamoDB-instance-with-Java-for-Integration-Testing) was covered in a previous post and I won&#39;t belabor that here. I&#39;ll just jump into the test case.

First, we have to set up our table to work with. This table will have:

- A composite primary key, where the partition key is &#34;Company&#34; \[of type string\] and &#34;Model&#34; \[also of type string\]
- A table name of &#34;DuplicateKeysTest&#34;
- A global secondary index \[called &#34;YearIndex&#34;\] that has a simple primary key of &#34;Year&#34; \[of type number\]

Here&#39;s the code, because it&#39;s java using the builder pattern, it&#39;s pretty verbose:

```java
    @Test
    public void gsiDuplicateKeysExample() throws Exception {
        String currentTableName = &#34;DuplicateKeysTest&#34;;
        String YEAR_GSI_NAME = &#34;YearIndex&#34;;

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

Now we&#39;ll populate some test data. We&#39;ll put three items in our table, all with the same hash attribute of &#34;Google&#34;, all with different range attributes, as well as two of them with a year attribute of &#34;2012&#34;.

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
        futurePhoneAttributes.put(YEAR, AttributeValue.builder().n(&#34;2012&#34;).build());
        putItem(currentTableName, futurePhoneAttributes);

        Map&lt;String, AttributeValue&gt; pixel2ItemAttributes = getMapWith(partitionKey, rangeKey3);
        pixel2ItemAttributes.put(COLOR, AttributeValue.builder().s(&#34;Cyan&#34;).build());
        pixel2ItemAttributes.put(YEAR, AttributeValue.builder().n(&#34;2014&#34;).build());
        putItem(currentTableName, pixel2ItemAttributes);

```

So now one of two things will happen, depending on the behavior of DynamoDB when it encounters duplicate primary keys in a global secondary index. Either it will overwrite the existing record or it will place them next to each other and allow us to get all the results that happen to share the same primary key.

It turns out that it does not overwrite on indexes \[as it does on the base table\] and instead allows you to get all the items with the same key. Here&#39;s the assertion that proves it:

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
                    queryResponse.count() == 2
                        &amp;&amp; queryResponse.items().stream().anyMatch(m -&gt; m.get(COLOR).s().equals(&#34;Blue&#34;))
                        &amp;&amp; queryResponse.items().stream().anyMatch(m -&gt; m.get(COLOR).s().equals(&#34;Silver&#34;))
                )
                .verifyComplete();

```

We verify that there are two items with the same hash key, then verify that they are unique by checking the &#34;Color&#34; attribute on those items

You should be able to clone the source repository and run this test, it will pass. Remember you can [check out the source code on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L565) and play around with this yourself.
