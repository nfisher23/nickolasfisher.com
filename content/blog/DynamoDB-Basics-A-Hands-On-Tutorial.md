---
title: "DynamoDB Basics: A Hands On Tutorial"
date: 2020-07-12T18:36:05
draft: false
tags: [distributed systems, DevOps, aws, dynamodb]
---

DynamoDB is a fully managed distributed datastore that does a great job of alleviating the operational overhead of building very scalable systems.

This tutorial is meant to give you a basic overview of how to bootstrap a local DynamoDB instance and then perform some basic operations on it. After this tutorial, I would recommend reading through [the documentation on the core components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html), if you haven&#39;t already.

## Local DynamoDB Setup

To work with dynamo locally, I just used [the docker image provided by AWS](https://hub.docker.com/r/amazon/dynamodb-local/). Simply create a **docker-compose.yaml** file like so:

```yaml
version: &#39;3.7&#39;
services:
  dynamodb-local:
    image: amazon/dynamodb-local
    container_name: dynamodb-local
    ports:
      - &#34;8000:8000&#34;

```

After you&#39;ve created this file, navigate in your shell to where it exists and run:

```bash
docker-compose up -d

```

Now that we have one running, we can start messing with it. First you&#39;ll need some AWS credentials \[locally, this container just looks for the existence of credentials, there is nothing magic about them. Obviously, up on AWS infrastructure they will have to be valid\]:

```bash
export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;

```

If you&#39;re just messing around on the command line, this should also help make your life easier:

```bash
alias awslocal=&#34;aws --endpoint-url http://localhost:8000 --region=us-west-2&#34;

```

We can verify the latter is working properly with:

```bash
awslocal dynamodb describe-limits

```

## Working with DynamoDB

At this point, we&#39;re ready to try a couple of basic operations. DynamoDB has a \[similar to, though more limited than, relational datastores\] concept of a table. We have to have a table to store any data, so I am going to create a table called **Phones**. This table will store at least the Company name that makes the phone as well as the product name of the phone. We can include any additional information once we have those two pieces of data established for an item.

I&#39;m going to structure table with a composite primary key. In Dynamo, a composite primary key is made up of a partition key and a sort key. The partition key is fed to a hash function by dynamo, and the output hash then determines where an item with that partition key is physically stored in the cluster. The sort key just says &#34;on this partition, I want you to keep these items physically close to each other, and ultimately keep them in order.&#34; This largely makes range queries more efficient. Here&#39;s what it looks like to create this using the AWS CLI:

```bash
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name Phones \
  --attribute-definitions AttributeName=Company,AttributeType=S AttributeName=Model,AttributeType=S \
  --key-schema AttributeName=Company,KeyType=HASH AttributeName=Model,KeyType=RANGE
```

Now we&#39;re going to add data to this table. An item in DynamoDB is very similar to a row in a relational database, and attributes \[in an item\] are very similar to the columns of that row. In dynamo, to add an item to a table, you use **put-item**. I&#39;ve created a template (used by **printf**) and a helper function to make this a bit easier, but here&#39;s the code:

```bash
#!/bin/bash

TEMPLATE=$(cat &lt;&lt;&#39;EOF&#39;
{
    &#34;Company&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    },
    &#34;Model&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    },
    &#34;Colors&#34;: {
        &#34;SS&#34;: [
            &#34;Green&#34;,
            &#34;Blue&#34;,
            &#34;Orange&#34;
        ]
    },
    &#34;Size&#34;: {
        &#34;N&#34;: &#34;%s&#34;
    }
}
EOF
)

put_dynamo_local() {
    ITEM=&#34;$1&#34;
    # echo $ITEM = json_pp
    # return 0
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb put-item \
      --table-name Phones \
      --item &#34;$ITEM&#34;
}

MOTO_COOL=$(printf &#34;$TEMPLATE&#34; &#34;Motorola&#34; &#34;Cool Phone&#34; &#34;12&#34;)
MOTO_LAME=$(printf &#34;$TEMPLATE&#34; &#34;Motorola&#34; &#34;Lame Phone&#34; &#34;9&#34;)
GOOGL_NICE=$(printf &#34;$TEMPLATE&#34; &#34;Goole&#34; &#34;Awesome Phone&#34; &#34;8&#34;)
GOOGL_CONF=$(printf &#34;$TEMPLATE&#34; &#34;Google&#34; &#34;Confusing Phone&#34; &#34;18&#34;)

put_dynamo_local &#34;$MOTO_COOL&#34;
put_dynamo_local &#34;$MOTO_LAME&#34;
put_dynamo_local &#34;$GOOGL_NICE&#34;
put_dynamo_local &#34;$GOOGL_CONF&#34;

```

We now have four items in our table. We can see the &#34;Model&#34; of the four items with a **scan** of all the items and some simple **jq** parsing:

```bash
$ aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb scan --table-name Phones | jq -r &#34;.Items | map(.Model.S) | .[]&#34;
Confusing Phone
Awesome Phone
Cool Phone
Lame Phone

```

The final operation I&#39;m going to point out in this intro is **querying**. If we want to get a single item out of dynamo with our composite primary key, we have to provide both the partition key as well as the sort key (you can also choose a range of acceptable values for the sort key, or just get all the items with the same partition key if that&#39;s what you want to do):

```bash
#!/bin/bash

EQ_TEMPLATE=$(cat &lt;&lt;&#39;EOF&#39;
{
    &#34;Company&#34;: {
        &#34;AttributeValueList&#34;: [
            {
                &#34;S&#34;: &#34;%s&#34;
            }
        ],
        &#34;ComparisonOperator&#34;: &#34;EQ&#34;
    },
    &#34;Model&#34;: {
        &#34;AttributeValueList&#34;: [
            {
                &#34;S&#34;: &#34;%s&#34;
            }
        ],
        &#34;ComparisonOperator&#34;: &#34;EQ&#34;
    }
}
EOF
)

query_local_dynamo() {
    ITEM=$1
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb query \
      --table-name Phones \
      --key-conditions &#34;$ITEM&#34;
}

MOTO_COOL=$(printf &#34;$EQ_TEMPLATE&#34; &#34;Motorola&#34; &#34;Cool Phone&#34;)

query_local_dynamo &#34;$MOTO_COOL&#34;
```

Here, you should get a response similar to this:

```json
{
    &#34;Items&#34;: [
        {
            &#34;Model&#34;: {
                &#34;S&#34;: &#34;Cool Phone&#34;
            },
            &#34;Company&#34;: {
                &#34;S&#34;: &#34;Motorola&#34;
            },
            &#34;Colors&#34;: {
                &#34;SS&#34;: [
                    &#34;Blue&#34;,
                    &#34;Green&#34;,
                    &#34;Orange&#34;
                ]
            },
            &#34;Size&#34;: {
                &#34;N&#34;: &#34;12&#34;
            }
        }
    ],
    &#34;Count&#34;: 1,
    &#34;ScannedCount&#34;: 1,
    &#34;ConsumedCapacity&#34;: null
}

```

Dynamo is simple at its core, but because of the tradeoffs that it needs to make in order to accomplish its high availability, I would recommend you get intimately familiar with it. Again, if you haven&#39;t already, check out the [core components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html).
