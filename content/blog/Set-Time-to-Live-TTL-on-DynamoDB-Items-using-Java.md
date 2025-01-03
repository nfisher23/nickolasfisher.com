---
title: "Set Time to Live [TTL] on DynamoDB Items using Java"
date: 2020-10-01T00:00:00
draft: false
---

In this post, we&#39;ll demonstrate how [expiring items in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html) works in java, using the AWS SDK 2.0&#43;, which has full reactive support.

We will leverage work done in a previous post, which [setup an embedded DynamoDB instance for integration testing](https://nickolasfisher.com/blog/Configuring-an-In-Memory-DynamoDB-instance-with-Java-for-Integration-Testing), and [the source code is available on Github](https://github.com/nfisher23/webflux-and-dynamo) for this and previous posts related to this topic.

## Background - How it Works

To start with, the things we&#39;ll need to understand to get TTL working are:

- You must first specify, at the table level, which attribute is the source of truth for when an item expires
- The attribute must specify the unix epoch time, in seconds, that the item should expire.
- Expiring an item, like many things in Dynamo, is a bit &#34;fuzzy&#34;--it will expire _around_ the time it is supposed to.


Further points and nuances can be found in the documentation for DynamoDB TTL, referenced at the start of this post.

## Table Setup

For this example, we&#39;ll start by setting up our table in the same way that we have in previous posts:

``` java
    @Test
    public void testTTL() throws Exception {
        String currentTableName = &#34;PhoneTTLTest&#34;;
        createTableAndWaitForComplete(currentTableName);
    }

```

This just leverages code we&#39;ve already written and I won&#39;t rehash that here.

After our test table is created, we will need to specify that TTL is enabled, as well as what attribute dynamo should be looking at to make the decision about when to expire an individual item. Note that in real environments \[e.g. production\] something like this should really be done with terraform, but this is just integration testing code so all is good:

``` java
        String EXPIRE_TIME = &#34;ExpireTime&#34;;
        dynamoDbAsyncClient.updateTimeToLive(
            UpdateTimeToLiveRequest.builder()
                .tableName(currentTableName)
                .timeToLiveSpecification(
                        TimeToLiveSpecification.builder()
                                .enabled(true)
                                .attributeName(EXPIRE_TIME)
                                .build()
                )
                .build()
        ).get();

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.describeTimeToLive(
                DescribeTimeToLiveRequest.builder().tableName(currentTableName).build()))
            )
            .expectNextMatches(describeTimeToLiveResponse -&gt;
                describeTimeToLiveResponse
                    .timeToLiveDescription()
                    .timeToLiveStatus().equals(TimeToLiveStatus.ENABLED)
            )
            .verifyComplete();

```

This chunk of code just sets the TTL specification, enabling TTL on this table and saying that the attribute of &#34;ExpireTime&#34; should be the source of truth for when an attribute should be expired. We then make a follow up call to verify that the settings we have specified on this table have actually taken effect.

Now let&#39;s put an item into this table, specify that it should expire soon, and see dynamo clear it out:

``` java
        String partitionKey = &#34;Google&#34;;
        String rangeKey = &#34;Pixel 1&#34;;

        Map&lt;String, AttributeValue&gt; pixel1ItemAttributes = getMapWith(partitionKey, rangeKey);
        pixel1ItemAttributes.put(COLOR, AttributeValue.builder().s(&#34;Blue&#34;).build());
        pixel1ItemAttributes.put(YEAR, AttributeValue.builder().n(&#34;2012&#34;).build());

        // expire about 3 seconds from now
        String expireTime = Long.toString((System.currentTimeMillis() / 1000L) &#43; 3);
        pixel1ItemAttributes.put(
                EXPIRE_TIME,
                AttributeValue.builder()
                        .n(expireTime)
                        .build()
        );

        PutItemRequest populateDataItemRequest = PutItemRequest.builder()
                .tableName(currentTableName)
                .item(pixel1ItemAttributes)
                .build();

        // put item with TTL into dynamo
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.putItem(populateDataItemRequest)))
                .expectNextCount(1)
                .verifyComplete();

        Map&lt;String, AttributeValue&gt; currentItemKey = Map.of(
                COMPANY, AttributeValue.builder().s(partitionKey).build(),
                MODEL, AttributeValue.builder().s(rangeKey).build()
        );

        // get immediately, should exist
        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder().tableName(currentTableName).key(currentItemKey).build()))
            )
            .expectNextMatches(getItemResponse -&gt; getItemResponse.hasItem()
                    &amp;&amp; getItemResponse.item().get(COLOR).s().equals(&#34;Blue&#34;))
            .verifyComplete();

        // local dynamo seems to need like 10 seconds to actually clear this out
        Thread.sleep(13000);

        StepVerifier.create(Mono.fromFuture(dynamoDbAsyncClient.getItem(
                GetItemRequest.builder()
                        .key(currentItemKey)
                        .tableName(currentTableName)
                        .build())
                )
            )
            .expectNextMatches(getItemResponse -&gt; !getItemResponse.hasItem())
            .verifyComplete();

```

Here, we set the expire time to be about 3 seconds from now on a created item, then immediately grab it from the table to verify that it exists. After a 13 second sleep \[necessary in this case basically because of the behavior of embedded/local dynamo\], we then verify that trying to get the same item out of the table returns an empty response.

Remember to [check out the source code](https://github.com/nfisher23/webflux-and-dynamo) for this one on Github.


