---
title: "DynamoDB Basics: A Hands On Tutorial"
date: 2020-07-12T18:36:05
draft: false
tags: [distributed systems, DevOps, aws, dynamodb]
---

DynamoDB is a fully managed distributed datastore that does a great job of alleviating the operational overhead of building very scalable systems.

This tutorial is meant to give you a basic overview of how to bootstrap a local DynamoDB instance and then perform some basic operations on it. After this tutorial, I would recommend reading through [the documentation on the core components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html), if you haven't already.

## Local DynamoDB Setup

To work with dynamo locally, I just used [the docker image provided by AWS](https://hub.docker.com/r/amazon/dynamodb-local/). Simply create a **docker-compose.yaml** file like so:

```yaml
version: '3.7'
services:
  dynamodb-local:
    image: amazon/dynamodb-local
    container_name: dynamodb-local
    ports:
      - "8000:8000"

```

After you've created this file, navigate in your shell to where it exists and run:

```bash
docker-compose up -d

```

Now that we have one running, we can start messing with it. First you'll need some AWS credentials \[locally, this container just looks for the existence of credentials, there is nothing magic about them. Obviously, up on AWS infrastructure they will have to be valid\]:

```bash
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"

```

If you're just messing around on the command line, this should also help make your life easier:

```bash
alias awslocal="aws --endpoint-url http://localhost:8000 --region=us-west-2"

```

We can verify the latter is working properly with:

```bash
awslocal dynamodb describe-limits

```

## Working with DynamoDB

At this point, we're ready to try a couple of basic operations. DynamoDB has a \[similar to, though more limited than, relational datastores\] concept of a table. We have to have a table to store any data, so I am going to create a table called **Phones**. This table will store at least the Company name that makes the phone as well as the product name of the phone. We can include any additional information once we have those two pieces of data established for an item.

I'm going to structure table with a composite primary key. In Dynamo, a composite primary key is made up of a partition key and a sort key. The partition key is fed to a hash function by dynamo, and the output hash then determines where an item with that partition key is physically stored in the cluster. The sort key just says "on this partition, I want you to keep these items physically close to each other, and ultimately keep them in order." This largely makes range queries more efficient. Here's what it looks like to create this using the AWS CLI:

```bash
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name Phones \
  --attribute-definitions AttributeName=Company,AttributeType=S AttributeName=Model,AttributeType=S \
  --key-schema AttributeName=Company,KeyType=HASH AttributeName=Model,KeyType=RANGE
```

Now we're going to add data to this table. An item in DynamoDB is very similar to a row in a relational database, and attributes \[in an item\] are very similar to the columns of that row. In dynamo, to add an item to a table, you use **put-item**. I've created a template (used by **printf**) and a helper function to make this a bit easier, but here's the code:

```bash
#!/bin/bash

TEMPLATE=$(cat <<'EOF'
{
    "Company": {
        "S": "%s"
    },
    "Model": {
        "S": "%s"
    },
    "Colors": {
        "SS": [
            "Green",
            "Blue",
            "Orange"
        ]
    },
    "Size": {
        "N": "%s"
    }
}
EOF
)

put_dynamo_local() {
    ITEM="$1"
    # echo $ITEM = json_pp
    # return 0
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb put-item \
      --table-name Phones \
      --item "$ITEM"
}

MOTO_COOL=$(printf "$TEMPLATE" "Motorola" "Cool Phone" "12")
MOTO_LAME=$(printf "$TEMPLATE" "Motorola" "Lame Phone" "9")
GOOGL_NICE=$(printf "$TEMPLATE" "Goole" "Awesome Phone" "8")
GOOGL_CONF=$(printf "$TEMPLATE" "Google" "Confusing Phone" "18")

put_dynamo_local "$MOTO_COOL"
put_dynamo_local "$MOTO_LAME"
put_dynamo_local "$GOOGL_NICE"
put_dynamo_local "$GOOGL_CONF"

```

We now have four items in our table. We can see the "Model" of the four items with a **scan** of all the items and some simple **jq** parsing:

```bash
$ aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb scan --table-name Phones | jq -r ".Items | map(.Model.S) | .[]"
Confusing Phone
Awesome Phone
Cool Phone
Lame Phone

```

The final operation I'm going to point out in this intro is **querying**. If we want to get a single item out of dynamo with our composite primary key, we have to provide both the partition key as well as the sort key (you can also choose a range of acceptable values for the sort key, or just get all the items with the same partition key if that's what you want to do):

```bash
#!/bin/bash

EQ_TEMPLATE=$(cat <<'EOF'
{
    "Company": {
        "AttributeValueList": [
            {
                "S": "%s"
            }
        ],
        "ComparisonOperator": "EQ"
    },
    "Model": {
        "AttributeValueList": [
            {
                "S": "%s"
            }
        ],
        "ComparisonOperator": "EQ"
    }
}
EOF
)

query_local_dynamo() {
    ITEM=$1
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb query \
      --table-name Phones \
      --key-conditions "$ITEM"
}

MOTO_COOL=$(printf "$EQ_TEMPLATE" "Motorola" "Cool Phone")

query_local_dynamo "$MOTO_COOL"
```

Here, you should get a response similar to this:

```json
{
    "Items": [
        {
            "Model": {
                "S": "Cool Phone"
            },
            "Company": {
                "S": "Motorola"
            },
            "Colors": {
                "SS": [
                    "Blue",
                    "Green",
                    "Orange"
                ]
            },
            "Size": {
                "N": "12"
            }
        }
    ],
    "Count": 1,
    "ScannedCount": 1,
    "ConsumedCapacity": null
}

```

Dynamo is simple at its core, but because of the tradeoffs that it needs to make in order to accomplish its high availability, I would recommend you get intimately familiar with it. Again, if you haven't already, check out the [core components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html).
