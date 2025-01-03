---
title: "Query a DynamoDB Local Secondary Index with Java"
date: 2020-10-31T22:49:54
draft: false
---

DynamoDB&#39;s Local Secondary Indexes allow for more query flexibility than a traditional partition and range key combination. They are also the only index in DynamoDB where a strongly consistent read can be requested \[global secondary indexes, the other index that dynamo supports, can at best be eventually consistent\]. I will walk through an example for how to use local secondary indexes in dynamo using the AWS SDK 2.0 for Java, which has full reactive support, in this post.

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L338).

## Creating the Table

A very important constraint of local secondary indexes is that you must create one **at table creation time**. You cannot modify an existing table to have a local secondary index, unlike traditional RDBMS systems.

We&#39;re going to be building off of previous posts where we have worked with DynamoDB, notably one where we showed [how to configure an embedded DynamoDB instance for integration testing](https://nickolasfisher.com/blog/Configuring-an-In-Memory-DynamoDB-instance-with-Java-for-Integration-Testing). I won&#39;t repeat the boilerplate code that was demonstrated there, and instead dive into this specific problem.

Since we have to define the index at table creation time, here is some java code to set up a table for us \[note: in a production or production-like environment, I would strongly recommend you use something like terraform to manage table creation/modification\]

```java
    @Test
    public void localSecondaryIndex() throws Exception {
        String currentTableName = &#34;LocalIndexTest&#34;;
        String COMPANY_YEAR_INDEX = &#34;CompanyYearIndex&#34;;
        LocalSecondaryIndex localSecondaryIndexSpec = LocalSecondaryIndex.builder()
                .keySchema(
                        KeySchemaElement.builder()
                                .keyType(KeyType.HASH)
                                .attributeName(COMPANY)
                                .build(),
                        KeySchemaElement.builder()
                                .keyType(KeyType.RANGE)
                                .attributeName(YEAR)
                                .build()
                )
                .indexName(COMPANY_YEAR_INDEX)
                .projection(Projection.builder()
                        .projectionType(ProjectionType.ALL)
                        .build()
                )
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
                .provisionedThroughput(ProvisionedThroughput.builder()
                        .readCapacityUnits(100L)
                        .writeCapacityUnits(100L).build()
                )
                .tableName(currentTableName)
                .localSecondaryIndexes(localSecondaryIndexSpec)
                .build()
        ).get();
    }

```

We start by setting up a **LocalSecondaryIndex** POJO, which specifies that the name of the index will be &#34;CompanyYearIndex&#34;, the range key on this index should be &#34;Year&#34;, and that we want to project all attributes onto this index. Projecting attributes is exactly what it sounds like: when the index is synced up with the primary item write, we can decide which attributes in the item we want to be available when the index is queried. In this case I&#39;m just sending all of them.

After specifying what we want the index to look like, we include that specification in the create table operation by using **localSecondaryIndexes** in the DSL. Note that we must also specify the **attributeType** of &#34;Year&#34; \[the range key on our index\], or the create table operation will fail.

## Setup data

Now we&#39;ll put some data into our newly created table. This follows the pattern/ [reuses code from some previous posts](https://nickolasfisher.com/blog/Querying-DynamoDB-in-Java-with-the-AWS-SDK-20) and I won&#39;t belabor it here:

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

We put three items into this table, all with the same hash attribute as &#34;Google&#34;; and different range attributes.

## Querying the Index

When we decide that we need to use an index, we have to specify the index at the time of querying \[if it is using a range attribute that is different from the range attribute associated with the base table\]. Let&#39;s say we want to get all Google phones after the year of 2013. Leveraging the index we just created, that could look something like:

```java
        Condition equalsGoogleCondition = Condition.builder()
                .comparisonOperator(ComparisonOperator.EQ)
                .attributeValueList(
                    AttributeValue.builder()
                            .s(partitionKey)
                            .build()
                )
                .build();

        Condition greaterThan2013Condition = Condition.builder()
                .comparisonOperator(ComparisonOperator.GT)
                .attributeValueList(
                    AttributeValue.builder()
                        .n(&#34;2013&#34;)
                        .build()
                )
                .build();

        QueryRequest yearAfter2013Query = QueryRequest.builder()
                .tableName(currentTableName)
                .keyConditions(
                    Map.of(
                        COMPANY, equalsGoogleCondition,
                        YEAR, greaterThan2013Condition
                    )
                )
                .indexName(COMPANY_YEAR_INDEX)
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.query(yearAfter2013Query)))
                .expectNextMatches(queryResponse -&gt;
                        queryResponse.count() == 2
                        &amp;&amp; queryResponse.items()
                            .stream()
                            .anyMatch(attributeValueMap -&gt; &#34;Pixel 2&#34;.equals(
                                    attributeValueMap.get(MODEL).s())
                            )
                )
                .verifyComplete();

```

Here, we create two **Condition** s \[think: query conditions\]. One gets used to indicate the hash key equals Google, the other is to indicate that the year associated with the item is strictly greater than 2013. We then use **indexName** in the DSL to specify that we need to use a specific index to pull this off. Finally, we validate the results are what we expect, leveraging **Mono** and **StepVerifier**. There is where our query is actually executed against dynamo and we get the response we are looking for \[two records, Pixel 2 and Future Phone\]. You should be able to run this test and see it pass.

Remember to [check out the source code for this article on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L338).
