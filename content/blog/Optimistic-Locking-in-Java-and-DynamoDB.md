---
title: "Optimistic Locking in Java and DynamoDB"
date: 2020-10-11T20:19:42
draft: false
tags: [java, reactive, aws, dynamodb]
---

I've previously written about using [conditional expressions to achieve optimistic locking in DynamoDB](https://nickolasfisher.com/blog/how-to-use-optimistic-locking-in-dynamodb-via-the-aws-cli), that example used the command line. I will now demonstrate how to do the same thing in java code, leveraging the AWS SDK 2.0 \[with full reactive support\].

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo), I set up an in memory DynamoDB instance, which isn't really the subject of this tutorial but made it very easy to test.

## Setup Data

Assuming everything is wired up correctly, first we need data to work with, so we will initiate the create table operation, then wait for that to complete:

```java
    public static final String COMPANY = "Company";
    public static final String MODEL = "Model";

    private CompletableFuture<CreateTableResponse> createTableAsync(String tableName) {
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

        Mono.fromFuture(() -> dynamoDbAsyncClient.describeTable(DescribeTableRequest.builder().tableName(currentTableName).build()))
                .flatMap(describeTableResponse -> {
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
        String currentTableName = "PhonesOptLocking";

        createTableAndWaitForComplete(currentTableName);
    }

```

This code leverages a **retry** on **Mono** to keep retrying in the case that the table isn't ready yet \[this might be a bit of over-engineering on my part, I haven't actually seen this yet\].

With this in place, let's add an item to this table. First here's a helper method:

```java
    private Map<String, AttributeValue> getMapWith(String companyName, String modelName) {
        Map<String, AttributeValue> map = new HashMap<>();

        map.put(COMPANY, AttributeValue.builder().s(companyName).build());
        map.put(MODEL, AttributeValue.builder().s(modelName).build());

        return map;
    }

```

And we can add to our test like so:

```java
        String stubCompanyName = "Nokia";
        String stubPhoneName = "flip-phone-1";

        Map<String, AttributeValue> itemAttributes = getMapWith(stubCompanyName, stubPhoneName);
        itemAttributes.put("Color", AttributeValue.builder().s("Orange").build());
        itemAttributes.put("Version", AttributeValue.builder().n(Long.valueOf(1L).toString()).build());

        PutItemRequest populateDataItemRequest = PutItemRequest.builder()
                .tableName(currentTableName)
                .item(itemAttributes)
                .build();

        // populate initial data
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(populateDataItemRequest)))
                .expectNextCount(1)
                .verifyComplete();

```

The configuration of this dynamo table necessitates that we include a **Company** and **Model**, because that is our primary key \[it's fair to think of this as a composite primary key for the most part, there are some minor differences\]. The total object we're inserting here looks like:

```json
{
    "Company": "Nokia",
    "Model": "flip-phone-1",
    "Color": "Orange",
    "Version": 1
}

```

Now for the fun part. Optimistic locking is often done by tracking the version on the item. If we read version 8 from the database, and then we write version 9, if there is another thread in the mix that also writes version 9, then there is a potential for data loss depending on the business use case. For this example we will follow that pattern, and we need to leverage conditional expressions.

If you haven't yet taken a look at the [reference for conditional expression in dynamodb](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.ConditionExpressions.html), I would suggest that you do so now. This is what it looks like in Java:

```java
        Map<String, AttributeValue> itemAttributesOptLocking = getMapWith(stubCompanyName, stubPhoneName);

        itemAttributesOptLocking.put("Color", AttributeValue.builder().s("Blue").build());
        itemAttributesOptLocking.put("Version", AttributeValue.builder().n(Long.valueOf(1L).toString()).build());

        Map<String, AttributeValue> expressionAttributeValues = new HashMap<>();
        expressionAttributeValues.put(":version", AttributeValue.builder().n("0").build());

        PutItemRequest conditionalPutItem = PutItemRequest.builder()
                .item(itemAttributes)
                .tableName(currentTableName)
                .conditionExpression("Version = :version")
                .expressionAttributeValues(expressionAttributeValues)
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(conditionalPutItem)))
                .expectErrorMatches(throwable -> throwable instanceof ConditionalCheckFailedException)
                .verify();
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder()
                        .tableName(currentTableName)
                        .key(getMapWith(stubCompanyName, stubPhoneName))
                        .build())
                ))
                // not blue, so our conditional expression prevented us from overwriting it
                .expectNextMatches(getItemResponse -> "Orange".equals(getItemResponse.item().get("Color").s()))
                .verifyComplete();

```

Here, we try to overwrite the existing item we just wrote with **version 0**. Since the version actually in dynamo will be 1, we can make this assertion:

```json>{
    "Company": "Nokia",
    "Model": "flip-phone-1",
    "Color": "Blue",
    "Version": 1
}
</code></pre>

<p>We also have a conditional expression checking for the version being equal to <strong>0</strong>. Because the version in dynamo is actually <strong>1</strong>, this conditional check fails and the record is not persisted. We verify that we first get an exception of type <strong>ConditionalCheckFailedException</strong> with this block:</p>

<pre><code class=
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(conditionalPutItem)))
                .expectErrorMatches(throwable -> throwable instanceof ConditionalCheckFailedException)
                .verify();

```

We then get the item in dynamo and verify that the color has not changed, it is correctly "Orange":

```java
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder()
                        .tableName(currentTableName)
                        .key(getMapWith(stubCompanyName, stubPhoneName))
                        .build())
                ))
                // not blue, so our conditional expression prevented us from overwriting it
                .expectNextMatches(getItemResponse -> "Orange".equals(getItemResponse.item().get("Color").s()))
                .verifyComplete();

```

You should be able to follow this pattern for your use case. Remember to [check out the code on Github](https://github.com/nfisher23/webflux-and-dynamo)!
