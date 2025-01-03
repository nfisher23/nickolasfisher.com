---
title: "Optimistic Locking in Java and DynamoDB"
date: 2020-10-01T00:00:00
draft: false
---

I&#39;ve previously written about using [conditional expressions to achieve optimistic locking in DynamoDB](https://nickolasfisher.com/blog/How-to-use-Optimistic-Locking-in-DynamoDB-via-the-AWS-CLI), that example used the command line. I will now demonstrate how to do the same thing in java code, leveraging the AWS SDK 2.0 \[with full reactive support\].

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo), I set up an in memory DynamoDB instance, which isn&#39;t really the subject of this tutorial but made it very easy to test.

## Setup Data

Assuming everything is wired up correctly, first we need data to work with, so we will initiate the create table operation, then wait for that to complete:

``` java
    public static final String COMPANY = &#34;Company&#34;;
    public static final String MODEL = &#34;Model&#34;;

    private CompletableFuture&lt;CreateTableResponse&gt; createTableAsync(String tableName) {
        return dynamoDbAsyncClient.createTable(CreateTableRequest.builder()
                .keySchema(
                        KeySchemaElement.builder().keyType(KeyType.HASH).attributeName(COMPANY).build(),
                        KeySchemaElement.builder().keyType(KeyType.RANGE).attributeName(MODEL).build()
                )
                .attributeDefinitions(
                        AttributeDefinition.builder().attributeName(COMPANY).attributeType(ScalarAttributeType.S).build(),
                        AttributeDefinition.builder().attributeName(MODEL).attributeType(ScalarAttributeType.S).build()
                )
                .provisionedThroughput(ProvisionedThroughput.builder().readCapacityUnits(100L).writeCapacityUnits(100L).build())
                .tableName(tableName)
                .build()
        );
    }

    private void createTableAndWaitForComplete(String currentTableName) throws InterruptedException, java.util.concurrent.ExecutionException {
        createTableAsync(currentTableName).get();

        Mono.fromFuture(() -&gt; dynamoDbAsyncClient.describeTable(DescribeTableRequest.builder().tableName(currentTableName).build()))
                .flatMap(describeTableResponse -&gt; {
                    if (describeTableResponse.table().tableStatus() == TableStatus.ACTIVE) {
                        return Mono.just(describeTableResponse);
                    } else {
                        return Mono.error(new RuntimeException());
                    }
                })
                .retry(100).block();
    }

    @Test
    public void testOptimisticLocking() throws Exception {
        String currentTableName = &#34;PhonesOptLocking&#34;;

        createTableAndWaitForComplete(currentTableName);
    }

```

This code leverages a **retry** on **Mono** to keep retrying in the case that the table isn&#39;t ready yet \[this might be a bit of over-engineering on my part, I haven&#39;t actually seen this yet\].

With this in place, let&#39;s add an item to this table. First here&#39;s a helper method:

``` java
    private Map&lt;String, AttributeValue&gt; getMapWith(String companyName, String modelName) {
        Map&lt;String, AttributeValue&gt; map = new HashMap&lt;&gt;();

        map.put(COMPANY, AttributeValue.builder().s(companyName).build());
        map.put(MODEL, AttributeValue.builder().s(modelName).build());

        return map;
    }

```

And we can add to our test like so:

``` java
        String stubCompanyName = &#34;Nokia&#34;;
        String stubPhoneName = &#34;flip-phone-1&#34;;

        Map&lt;String, AttributeValue&gt; itemAttributes = getMapWith(stubCompanyName, stubPhoneName);
        itemAttributes.put(&#34;Color&#34;, AttributeValue.builder().s(&#34;Orange&#34;).build());
        itemAttributes.put(&#34;Version&#34;, AttributeValue.builder().n(Long.valueOf(1L).toString()).build());

        PutItemRequest populateDataItemRequest = PutItemRequest.builder()
                .tableName(currentTableName)
                .item(itemAttributes)
                .build();

        // populate initial data
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(populateDataItemRequest)))
                .expectNextCount(1)
                .verifyComplete();

```

The configuration of this dynamo table necessitates that we include a **Company** and **Model**, because that is our primary key \[it&#39;s fair to think of this as a composite primary key for the most part, there are some minor differences\]. The total object we&#39;re inserting here looks like:

``` json
{
    &#34;Company&#34;: &#34;Nokia&#34;,
    &#34;Model&#34;: &#34;flip-phone-1&#34;,
    &#34;Color&#34;: &#34;Orange&#34;,
    &#34;Version&#34;: 1
}

```

Now for the fun part. Optimistic locking is often done by tracking the version on the item. If we read version 8 from the database, and then we write version 9, if there is another thread in the mix that also writes version 9, then there is a potential for data loss depending on the business use case. For this example we will follow that pattern, and we need to leverage conditional expressions.

If you haven&#39;t yet taken a look at the [reference for conditional expression in dynamodb](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.ConditionExpressions.html), I would suggest that you do so now. This is what it looks like in Java:

``` java
        Map&lt;String, AttributeValue&gt; itemAttributesOptLocking = getMapWith(stubCompanyName, stubPhoneName);

        itemAttributesOptLocking.put(&#34;Color&#34;, AttributeValue.builder().s(&#34;Blue&#34;).build());
        itemAttributesOptLocking.put(&#34;Version&#34;, AttributeValue.builder().n(Long.valueOf(1L).toString()).build());

        Map&lt;String, AttributeValue&gt; expressionAttributeValues = new HashMap&lt;&gt;();
        expressionAttributeValues.put(&#34;:version&#34;, AttributeValue.builder().n(&#34;0&#34;).build());

        PutItemRequest conditionalPutItem = PutItemRequest.builder()
                .item(itemAttributes)
                .tableName(currentTableName)
                .conditionExpression(&#34;Version = :version&#34;)
                .expressionAttributeValues(expressionAttributeValues)
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(conditionalPutItem)))
                .expectErrorMatches(throwable -&gt; throwable instanceof ConditionalCheckFailedException)
                .verify();
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder()
                        .tableName(currentTableName)
                        .key(getMapWith(stubCompanyName, stubPhoneName))
                        .build())
                ))
                // not blue, so our conditional expression prevented us from overwriting it
                .expectNextMatches(getItemResponse -&gt; &#34;Orange&#34;.equals(getItemResponse.item().get(&#34;Color&#34;).s()))
                .verifyComplete();

```

Here, we try to overwrite the existing item we just wrote with **version 0**. Since the version actually in dynamo will be 1, we can make this assertion:

```java
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(conditionalPutItem)))
                .expectErrorMatches(throwable -&gt; throwable instanceof ConditionalCheckFailedException)
                .verify();

```

We then get the item in dynamo and verify that the color has not changed, it is correctly &#34;Orange&#34;:

``` java
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder()
                        .tableName(currentTableName)
                        .key(getMapWith(stubCompanyName, stubPhoneName))
                        .build())
                ))
                // not blue, so our conditional expression prevented us from overwriting it
                .expectNextMatches(getItemResponse -&gt; &#34;Orange&#34;.equals(getItemResponse.item().get(&#34;Color&#34;).s()))
                .verifyComplete();

```

You should be able to follow this pattern for your use case. Remember to [check out the code on Github](https://github.com/nfisher23/webflux-and-dynamo)!


