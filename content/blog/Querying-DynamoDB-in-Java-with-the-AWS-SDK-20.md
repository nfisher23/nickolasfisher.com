---
title: "Querying DynamoDB in Java with the AWS SDK 2.0"
date: 2020-10-01T00:00:00
draft: false
---

Queries in DynamoDB allow you to find data. This is only an option to you if your table has a partition and sort key.

This post will demonstrate a couple different ways to get querying to work in java, using the AWS SDK v2, with full reactive support. [The source code is available on Github](https://github.com/nfisher23/webflux-and-dynamo).

## Setting up the data

We will be building off of a previous post that [set up an in memory \[embedded\] dynamo instance](https://nickolasfisher.com/blog/Configuring-an-In-Memory-DynamoDB-instance-with-Java-for-Integration-Testing) to save us time and energy. In that post, if you recall, we had a **hash key named &#34;Company&#34; and a range key named &#34;Phones&#34;**, which presumably is to store a catalog of different companies that manufacture different phones.

We will follow the same pattern as before where we are writing an integration test to describe much of this behavior. First, let&#39;s set up some metadata and create this table:

``` java
    @Test
    public void testQueries() throws Exception {
        String currentTableName = &#34;PhonesQueriesTest&#34;;
        createTableAndWaitForComplete(currentTableName);

        String partitionKey = &#34;Google&#34;;
        String rangeKey1 = &#34;Pixel 1&#34;;
        String rangeKey2 = &#34;Future Phone&#34;;
        String rangeKey3 = &#34;Pixel 2&#34;;

        String COLOR = &#34;Color&#34;;
        String YEAR = &#34;Year&#34;;

    }

```

The method mentioned here to create the table looks contains code like this, and is probably only relevant for setting up tests like this \[I would recommend using something like terraform to manage dynamo tables in the cloud, rather than java code\]:

``` java
    private CompletableFuture&lt;CreateTableResponse&gt; createTableAsync(String tableName) {
        return dynamoDbAsyncClient.createTable(CreateTableRequest.builder()
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
                                .build()
                )
                .provisionedThroughput(ProvisionedThroughput.builder().readCapacityUnits(100L).writeCapacityUnits(100L).build())
                .tableName(tableName)
                .build()
        );
    }

```

Alright, so now we&#39;ve got our table, we&#39;re going to create three items, each with the same partition key as **Google**. The range keys will be **Pixel 1**,
**Pixel 2**, and **Future Phone**:

``` java
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

And I&#39;ll note again some helper methods outlined above:

``` java
    private void putItem(String tableName, Map&lt;String, AttributeValue&gt; attributes) {
        PutItemRequest populateDataItemRequest = PutItemRequest.builder()
                .tableName(tableName)
                .item(attributes)
                .build();

        // populate initial data
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(populateDataItemRequest)))
                .expectNextCount(1)
                .verifyComplete();
    }

    private Map&lt;String, AttributeValue&gt; getMapWith(String companyName, String modelName) {
        Map&lt;String, AttributeValue&gt; map = new HashMap&lt;&gt;();

        map.put(COMPANY, AttributeValue.builder().s(companyName).build());
        map.put(MODEL, AttributeValue.builder().s(modelName).build());

        return map;
    }

```

With this in place, let&#39;s demonstrate querying.

## Querying Now

To start with, we have to provide at least one partition key in a **Key Condition Expression**. In this case we also have a range key, so specifying just the partition key will grab all of the range keys:

``` java
        // get all items associated with the &#34;Google&#34; partition key
        Condition equalsGoogleCondition = Condition.builder()
                .comparisonOperator(ComparisonOperator.EQ)
                .attributeValueList(
                    AttributeValue.builder()
                        .s(partitionKey)
                        .build()
                )
                .build();

        QueryRequest hashKeyIsGoogleQuery = QueryRequest.builder()
                .tableName(currentTableName)
                .keyConditions(Map.of(COMPANY, equalsGoogleCondition))
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.query(hashKeyIsGoogleQuery)))
                .expectNextMatches(queryResponse -&gt; queryResponse.count() == 3
                        &amp;&amp; queryResponse.items()
                            .stream()
                            .anyMatch(attributeValueMap -&gt; &#34;2012&#34;.equals(
                                attributeValueMap.get(YEAR).n())
                            )
                )
                .verifyComplete();

```

Here, we get all of the items associated with a particular partition key, which as a reminder in this case is **Google**, and then we assert that we get three items back and that at least one of them has a **Year** attribute of **2012**. This part of the test passes.

Let&#39;s do one more. Let&#39;s say we want to get all the models of the phones produced by Google that were of the **Pixel** family. Assuming we are versioning all the Pixel phones such that they start with the word &#34;Pixel&#34;, we can do the following:

``` java
        // Get all items that start with &#34;Pixel&#34;
        Condition startsWithPixelCondition = Condition.builder()
                .comparisonOperator(ComparisonOperator.BEGINS_WITH)
                .attributeValueList(
                        AttributeValue.builder()
                                .s(&#34;Pixel&#34;)
                                .build()
                )
                .build();

        QueryRequest equalsGoogleAndStartsWithPixelQuery = QueryRequest.builder()
                .tableName(currentTableName)
                .keyConditions(Map.of(
                        COMPANY, equalsGoogleCondition,
                        MODEL, startsWithPixelCondition
                ))
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.query(equalsGoogleAndStartsWithPixelQuery)))
                .expectNextMatches(queryResponse -&gt; queryResponse.count() == 2)
                .verifyComplete();

```

And with that, you should have a good starting point for experimenting more yourself. Reminder that you can [check out the source code for this post on githu](https://github.com/nfisher23/webflux-and-dynamo) b


