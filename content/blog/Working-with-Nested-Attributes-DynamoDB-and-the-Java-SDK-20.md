---
title: "Working with Nested Attributes, DynamoDB, and the Java SDK 2.0"
date: 2020-11-01T00:00:00
draft: false
---

[Nested attributes in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.Attributes.html) are a way to group data within an item together. The attributes are said to be nested if they are embedded within another attribute.

Building off a previous post where we [set up an embedded DynamoDB instance in a java test suite](https://nickolasfisher.com/blog/Configuring-an-In-Memory-DynamoDB-instance-with-Java-for-Integration-Testing), I&#39;ll provide here some examples for working with nested attributes.

The source code that follows [can be seen on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L722).

First let&#39;s create a table and insert some data:

``` java

    @Test
    public void nestedAttributes() throws Exception {
        String currentTableName = &#34;NestedAttributesTest&#34;;
        createTableAndWaitForComplete(currentTableName);

        Map&lt;String, AttributeValue&gt; attributes = Map.of(
                COMPANY, AttributeValue.builder().s(&#34;Motorola&#34;).build(),
                MODEL, AttributeValue.builder().s(&#34;G1&#34;).build(),
                &#34;MetadataList&#34;, AttributeValue.builder().l(
                        AttributeValue.builder().s(&#34;Super Cool&#34;).build(),
                        AttributeValue.builder().n(&#34;100&#34;).build()).build(),
                &#34;MetadataStringSet&#34;, AttributeValue.builder().ss(&#34;one&#34;, &#34;two&#34;, &#34;three&#34;).build(),
                &#34;MetadataNumberSet&#34;, AttributeValue.builder()
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

Given the primary key as a composite partition and sort key, where here it is &#34;Motorola&#34; as the partition and &#34;G1&#34; as the sort, there are three nested attribute types in play:

- **A list of attributes**. Note that these could be further nested attributes if we want, in this case we just put two scalar attributes in \[string and number\]
- **String Set**. This is exactly what it sounds like: a set of string values.
- **Binary Set**. This is also what it sounds like: a set of binary values. Each binary value \[as are all binary values\] is just a bunch of bytes.

Note that we omitted one set type of the three that are available, which is the number set.

We can now get this item out of dynamo, and the access patterns should be familiar to us at this point:

``` java
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(currentTableName)
                .key(getMapWith(&#34;Motorola&#34;, &#34;G1&#34;))
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(getItemRequest)))
                .expectNextMatches(getItemResponse -&gt; {
                    List&lt;AttributeValue&gt; listOfMetadata = getItemResponse.item().get(&#34;MetadataList&#34;).l();
                    List&lt;String&gt; stringSetMetadata = getItemResponse.item().get(&#34;MetadataStringSet&#34;).ss();

                    return listOfMetadata.size() == 2
                            &amp;&amp; listOfMetadata.stream().anyMatch(attributeValue -&gt; &#34;Super Cool&#34;.equals(attributeValue.s()))
                            &amp;&amp; listOfMetadata.stream().anyMatch(attributeValue -&gt; &#34;100&#34;.equals(attributeValue.n()))
                            &amp;&amp; stringSetMetadata.contains(&#34;one&#34;)
                            &amp;&amp; stringSetMetadata.contains(&#34;two&#34;);
                }).verifyComplete();
    }

```

Here, we get both the list of attributes and the string set from our item, then making assertions that they all are there and correct.

Remember to [check out the source code for this post](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L722) on Github.


