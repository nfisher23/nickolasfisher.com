---
title: "How to use Optimistic Locking in DynamoDB via the AWS CLI"
date: 2020-08-01T20:46:28
draft: false
tags: [bash, DevOps, aws, dynamodb]
---

Optimistic Locking is a form of concurrency control that basically aims to prevent two different threads from accidentally overwriting data that another thread has already written. I covered [optimistic locking in MySQL](https://nickolasfisher.com/blog/Optimistic-Locking-in-MySQLExplain-Like-Im-Five) in a previous blog post, which may or may not be easier to understand based on your background.

DynamoDB offers [conditional expressions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.ConditionExpressions.html) that can fulfill the same purpose for us here. I'll demonstrate an example that should fill the gap for most common use cases.

## Setup Local Environment And Data

Here's a dynamo local container in a docker compose file:

```yaml
version: '3.7'
services:
  dynamodb-local:
    image: amazon/dynamodb-local
    container_name: dynamodb-local
    ports:
      - "8000:8000"

```

Start this up with:

```bash
$ docker-compose up -d

```

If you do not have any valid AWS credentials on your local, you will have to set some fake ones or the CLI will complain:

```bash
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"

```

Now we'll create a table for the purposes of this tutorial, then create a sample record to work with:

```bash
#!/bin/bash

aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name Phones \
  --attribute-definitions AttributeName=Company,AttributeType=S AttributeName=Model,AttributeType=S \
  --key-schema AttributeName=Company,KeyType=HASH AttributeName=Model,KeyType=RANGE

FULL_ITEM_TEMPLATE=$(cat <<'EOF'
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
    },
    "Version": {
        "N": "%s"
    }
}
EOF
)

put_dynamo_local() {
    ITEM="$1"
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb put-item \
      --table-name Phones \
      --item "$ITEM"
}

MOTO_COOL=$(printf "$FULL_ITEM_TEMPLATE" "Motorola" "Cool Phone" "12" "1")
put_dynamo_local "$MOTO_COOL"

```

We have created a table called **Phones**. This table has a partition key of **Company** and a range key of **Model**. We placed one item in this table. Critically, this
item has an attribute named **Version**. We will use this version attribute in the same way we use it in MySQL to accomplish our goals here.

## Using update-item

The first operation we can demonstrate conditional updates on is [update-item](https://docs.aws.amazon.com/cli/latest/reference/dynamodb/update-item.html). This doesn't replace the entry in its entirety, but is rather meant to be used to operate on specific attributes in your item. For example, we can just execute a non-conditional update by setting the size on our record to be 100:

```bash
KEY_TEMPLATE=$(cat <<EOF
{
    "Company": {
        "S": "%s"
    },
    "Model": {
        "S": "%s"
    }
}
EOF
)

MOTO_COOL_KEY=$(printf "$KEY_TEMPLATE" "Motorola" "Cool Phone")

SIZE_EXP_ATTR_VAL_TEMPLATE=$(cat <<EOF
{
    ":size": {
        "S": "%s"
    }
}
EOF
)

SIZE_100=$(printf "$SIZE_EXP_ATTR_VAL_TEMPLATE" "100")

aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb update-item \
    --table-name Phones \
    --key "$MOTO_COOL_KEY" \
    --update-expression "SET Size = :size" \
    --expression-attribute-values "$SIZE_100"

```

If we now query for the record then we will see our changes reflected. Here's a script I've called **query.sh**, which you can use to verify changes at any point during this tutorial:

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

After the operations above, if you run **query.sh**, you should see this returned to you:

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
            "Version": {
                "N": "2"
            },
            "Size": {
                "S": "200"
            }
        }
    ],
    "Count": 1,
    "ScannedCount": 1,
    "ConsumedCapacity": null
}

```

We can add a **condition-expression** to update only when our passed in condition is true. In our case, we want to both increment the version and make sure that the current version is what we assume it is:

```bash
SIZE_CURR_VERSION_TEMPLATE=$(cat <<EOF
{
    ":size": {
        "S": "%s"
    },
    ":curr_version": {
        "N": "%s"
    },
    ":new_version": {
        "N": "%s"
    }
}
EOF
)

# update size to 200 if version is 1, also increment version to 2
SIZE_200=$(printf "$SIZE_CURR_VERSION_TEMPLATE" "200" "1" "2")
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb update-item \
    --table-name Phones \
    --key "$MOTO_COOL_KEY" \
    --update-expression "SET Size = :size, Version = :new_version" \
    --condition-expression "Version = :curr_version" \
    --expression-attribute-values "$SIZE_200"

```

You should see this reflected if you query dynamo using the script above.

To prove that it actually fails when it should fail, we can try to set the size to 300, but only if the version is 1. If you ran the code from above you should see this fail:

```bash
# ..someone else is trying to update size to 300 if the version is 1, also trying to set to version 2, fails!
SIZE_300=$(printf "$SIZE_CURR_VERSION_TEMPLATE" "300" "1" "2")
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb update-item \
    --table-name Phones \
    --key "$MOTO_COOL_KEY" \
    --update-expression "SET Size = :size, Version = :new_version" \
    --condition-expression "Version = :curr_version" \
    --expression-attribute-values "$SIZE_300"

```

Output:

```bash
An error occurred (ConditionalCheckFailedException) when calling the UpdateItem operation: The conditional request failed

```

If you run the query, you will also see that the size is still 200 while the version remains at 2.

You will notice that this **--condition-expression** is also a parameter option on the **put-item** operation, thus this pattern will work for the two most common operations against a dynamo item.
