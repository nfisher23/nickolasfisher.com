---
title: "Working with Nested Attributes, DynamoDB, and the Java SDK 2.0"
date: 2020-11-15T22:59:11
draft: false
tags: [java, distributed systems, aws, dynamodb]
---

[Nested attributes in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.Attributes.html) are a way to group data within an item together. The attributes are said to be nested if they are embedded within another attribute.

Building off a previous post where we [set up an embedded DynamoDB instance in a java test suite](https://nickolasfisher.com/blog/configuring-an-in-memory-dynamodb-instance-with-java-for-integration-testing), I'll provide here some examples for working with nested attributes.

The source code that follows [can be seen on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L722).

First let's create a table and insert some data:

```java

    @Test
    public void nestedAttributes() throws Exception {
        String currentTableName = "NestedAttributesTest";
        createTableAndWaitForComplete(currentTableName);

        Map<String, AttributeValue> attributes = Map.of(
                COMPANY, AttributeValue.builder().s("Motorola").build(),
                MODEL, AttributeValue.builder().s("G1").build(),
                "MetadataList", AttributeValue.builder().l(
                        AttributeValue.builder().s("Super Cool").build(),
                        AttributeValue.builder().n("100").build()).build(),
                "MetadataStringSet", AttributeValue.builder().ss("one", "two", "three").build(),
                "MetadataNumberSet", AttributeValue.builder()
                        .bs(SdkBytes.fromByteArray(new byte[] {43, 123}), SdkBytes.fromByteArray(new byte[] {78, 100}))
                        .build()
            );

        PutItemRequest populateDataItemRequest = PutItemRequest.builder()
                .tableName(currentTableName)
                .item(attributes)
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(populateDataItemRequest)))
                .expectNextCount(1)
                .verifyComplete();

```

Given the primary key as a composite partition and sort key, where here it is "Motorola" as the partition and "G1" as the sort, there are three nested attribute types in play:

- **A list of attributes**. Note that these could be further nested attributes if we want, in this case we just put two scalar attributes in \[string and number\]
- **String Set**. This is exactly what it sounds like: a set of string values.
- **Binary Set**. This is also what it sounds like: a set of binary values. Each binary value \[as are all binary values\] is just a bunch of bytes.

Note that we omitted one set type of the three that are available, which is the number set.

We can now get this item out of dynamo, and the access patterns should be familiar to us at this point:

```java
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(currentTableName)
                .key(getMapWith("Motorola", "G1"))
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(getItemRequest)))
                .expectNextMatches(getItemResponse -> {
                    List<AttributeValue> listOfMetadata = getItemResponse.item().get("MetadataList").l();
                    List<String> stringSetMetadata = getItemResponse.item().get("MetadataStringSet").ss();

                    return listOfMetadata.size() == 2
                            &amp;&amp; listOfMetadata.stream().anyMatch(attributeValue -> "Super Cool".equals(attributeValue.s()))
                            &amp;&amp; listOfMetadata.stream().anyMatch(attributeValue -> "100".equals(attributeValue.n()))
                            &amp;&amp; stringSetMetadata.contains("one")
                            &amp;&amp; stringSetMetadata.contains("two");
                }).verifyComplete();
    }

```

Here, we get both the list of attributes and the string set from our item, then making assertions that they all are there and correct.

Remember to [check out the source code for this post](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L722) on Github.
