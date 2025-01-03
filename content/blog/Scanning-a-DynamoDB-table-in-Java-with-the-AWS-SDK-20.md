---
title: "Scanning a DynamoDB table in Java with the AWS SDK 2.0"
date: 2020-11-07T02:08:37
draft: false
tags: [java, aws, dynamodb]
---

[Scanning in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Scan.html) is exactly what it sounds like: loop through every single record in a table, optionally filtering for items with a certain condition when dynamo returns them to you. In general, you _shouldn&#39;t do this_. DynamoDB is designed to store and manage a very large amount of data. Scanning through a large amount of data is very expensive, even in a distributed world. In the best case, you&#39;ll be waiting a long time to see results. In the worst case, you might see service outages as you burn through your RCUs.

But, if you&#39;re sure you want to do it, here&#39;s how. The [source code for everything that follows can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L670).

## Setup Table, Test Data

Building off of previous posts, in particular one where we setup an embedded DynamoDB instance in Java, I&#39;ll start by creating a table with a hash and range key \[&#34;Company&#34; and &#34;Model&#34;, both strings\], then putting three items in it:

```java
    @Test
    public void scanning() throws Exception {
        String currentTableName = &#34;ScanTest&#34;;
        createTableAndWaitForComplete(currentTableName);

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
    }

```

With this in place, we can start scanning. If we include no filter, then scanning will return everything back to us. If there are so many items that they exceed certain quotas, then there will be pagination. In this case, three items isn&#39;t big enough for dynamo to bother with pagination:

```java

        // scan everything, return everything
        ScanRequest scanEverythingRequest = ScanRequest.builder().tableName(currentTableName).build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.scan(scanEverythingRequest)))
                .expectNextMatches(scanResponse -&gt; scanResponse.scannedCount() == 3
                        &amp;&amp; scanResponse.items().size() == 3
                )
                .verifyComplete();

```

We can also include a filter expression to limit the number of results. Critically, we can note that we _still scan the entire table_ despite the existence of the filter expression. This is because attributes in an item are not indexed by default, and if you want to index them you need to create an index and then explicitly use that index.

Here, we include a filter expression on the color being &#34;Cyan&#34;:

```java

        // scan everything, return just items with Color == &#34;Cyan&#34;
        ScanRequest scanForCyanRequest = ScanRequest.builder()
                .tableName(currentTableName)
                .filterExpression(&#34;Color = :color&#34;)
                .expressionAttributeValues(Map.of(&#34;:color&#34;, AttributeValue.builder().s(&#34;Cyan&#34;).build()))
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.scan(scanForCyanRequest)))
                .expectNextMatches(scanResponse -&gt; scanResponse.scannedCount() == 3
                        &amp;&amp; scanResponse.items().size() == 1
                        &amp;&amp; scanResponse.items().get(0).get(&#34;Year&#34;).n().equals(&#34;2014&#34;)
                )
                .verifyComplete();

```

Feel free to [get the source code from Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L670) and play around with it yourself. You will be able to run this integration test and see it pass.
