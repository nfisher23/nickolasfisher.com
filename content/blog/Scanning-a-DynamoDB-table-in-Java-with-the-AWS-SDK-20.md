---
title: "Scanning a DynamoDB table in Java with the AWS SDK 2.0"
date: 2020-11-07T02:08:37
draft: false
tags: [java, aws, dynamodb]
---

[Scanning in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Scan.html) is exactly what it sounds like: loop through every single record in a table, optionally filtering for items with a certain condition when dynamo returns them to you. In general, you _shouldn't do this_. DynamoDB is designed to store and manage a very large amount of data. Scanning through a large amount of data is very expensive, even in a distributed world. In the best case, you'll be waiting a long time to see results. In the worst case, you might see service outages as you burn through your RCUs.

But, if you're sure you want to do it, here's how. The [source code for everything that follows can be found on Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L670).

## Setup Table, Test Data

Building off of previous posts, in particular one where we setup an embedded DynamoDB instance in Java, I'll start by creating a table with a hash and range key \["Company" and "Model", both strings\], then putting three items in it:

```java
    @Test
    public void scanning() throws Exception {
        String currentTableName = "ScanTest";
        createTableAndWaitForComplete(currentTableName);

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
        futurePhoneAttributes.put(YEAR, AttributeValue.builder().n("2030").build());
        putItem(currentTableName, futurePhoneAttributes);

        Map<String, AttributeValue> pixel2ItemAttributes = getMapWith(partitionKey, rangeKey3);
        pixel2ItemAttributes.put(COLOR, AttributeValue.builder().s("Cyan").build());
        pixel2ItemAttributes.put(YEAR, AttributeValue.builder().n("2014").build());
        putItem(currentTableName, pixel2ItemAttributes);
    }

```

With this in place, we can start scanning. If we include no filter, then scanning will return everything back to us. If there are so many items that they exceed certain quotas, then there will be pagination. In this case, three items isn't big enough for dynamo to bother with pagination:

```java

        // scan everything, return everything
        ScanRequest scanEverythingRequest = ScanRequest.builder().tableName(currentTableName).build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.scan(scanEverythingRequest)))
                .expectNextMatches(scanResponse -> scanResponse.scannedCount() == 3
                        &amp;&amp; scanResponse.items().size() == 3
                )
                .verifyComplete();

```

We can also include a filter expression to limit the number of results. Critically, we can note that we _still scan the entire table_ despite the existence of the filter expression. This is because attributes in an item are not indexed by default, and if you want to index them you need to create an index and then explicitly use that index.

Here, we include a filter expression on the color being "Cyan":

```java

        // scan everything, return just items with Color == "Cyan"
        ScanRequest scanForCyanRequest = ScanRequest.builder()
                .tableName(currentTableName)
                .filterExpression("Color = :color")
                .expressionAttributeValues(Map.of(":color", AttributeValue.builder().s("Cyan").build()))
                .build();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.scan(scanForCyanRequest)))
                .expectNextMatches(scanResponse -> scanResponse.scannedCount() == 3
                        &amp;&amp; scanResponse.items().size() == 1
                        &amp;&amp; scanResponse.items().get(0).get("Year").n().equals("2014")
                )
                .verifyComplete();

```

Feel free to [get the source code from Github](https://github.com/nfisher23/webflux-and-dynamo/blob/master/src/test/java/com/nickolasfisher/reactivedynamo/PhoneServiceTest.java#L670) and play around with it yourself. You will be able to run this integration test and see it pass.
