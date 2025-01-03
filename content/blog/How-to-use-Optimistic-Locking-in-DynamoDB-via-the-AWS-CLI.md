---
title: "How to use Optimistic Locking in DynamoDB via the AWS CLI"
date: 2020-08-01T20:46:28
draft: false
tags: [bash, DevOps, aws, dynamodb]
---

Optimistic Locking is a form of concurrency control that basically aims to prevent two different threads from accidentally overwriting data that another thread has already written. I covered [optimistic locking in MySQL](https://nickolasfisher.com/blog/Optimistic-Locking-in-MySQLExplain-Like-Im-Five) in a previous blog post, which may or may not be easier to understand based on your background.

DynamoDB offers [conditional expressions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.ConditionExpressions.html) that can fulfill the same purpose for us here. I&#39;ll demonstrate an example that should fill the gap for most common use cases.

## Setup Local Environment And Data

Here&#39;s a dynamo local container in a docker compose file:

```yaml
version: &#39;3.7&#39;
services:
  dynamodb-local:
    image: amazon/dynamodb-local
    container_name: dynamodb-local
    ports:
      - &#34;8000:8000&#34;

```

Start this up with:

```bash
$ docker-compose up -d

```

If you do not have any valid AWS credentials on your local, you will have to set some fake ones or the CLI will complain:

```bash
export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;

```

Now we&#39;ll create a table for the purposes of this tutorial, then create a sample record to work with:

```bash
#!/bin/bash

aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name Phones \
  --attribute-definitions AttributeName=Company,AttributeType=S AttributeName=Model,AttributeType=S \
  --key-schema AttributeName=Company,KeyType=HASH AttributeName=Model,KeyType=RANGE

FULL_ITEM_TEMPLATE=$(cat &lt;&lt;&#39;EOF&#39;
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
    },
    &#34;Version&#34;: {
        &#34;N&#34;: &#34;%s&#34;
    }
}
EOF
)

put_dynamo_local() {
    ITEM=&#34;$1&#34;
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb put-item \
      --table-name Phones \
      --item &#34;$ITEM&#34;
}

MOTO_COOL=$(printf &#34;$FULL_ITEM_TEMPLATE&#34; &#34;Motorola&#34; &#34;Cool Phone&#34; &#34;12&#34; &#34;1&#34;)
put_dynamo_local &#34;$MOTO_COOL&#34;

```

We have created a table called **Phones**. This table has a partition key of **Company** and a range key of **Model**. We placed one item in this table. Critically, this
item has an attribute named **Version**. We will use this version attribute in the same way we use it in MySQL to accomplish our goals here.

## Using update-item

The first operation we can demonstrate conditional updates on is [update-item](https://docs.aws.amazon.com/cli/latest/reference/dynamodb/update-item.html). This doesn&#39;t replace the entry in its entirety, but is rather meant to be used to operate on specific attributes in your item. For example, we can just execute a non-conditional update by setting the size on our record to be 100:

```bash
KEY_TEMPLATE=$(cat &lt;&lt;EOF
{
    &#34;Company&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    },
    &#34;Model&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    }
}
EOF
)

MOTO_COOL_KEY=$(printf &#34;$KEY_TEMPLATE&#34; &#34;Motorola&#34; &#34;Cool Phone&#34;)

SIZE_EXP_ATTR_VAL_TEMPLATE=$(cat &lt;&lt;EOF
{
    &#34;:size&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    }
}
EOF
)

SIZE_100=$(printf &#34;$SIZE_EXP_ATTR_VAL_TEMPLATE&#34; &#34;100&#34;)

aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb update-item \
    --table-name Phones \
    --key &#34;$MOTO_COOL_KEY&#34; \
    --update-expression &#34;SET Size = :size&#34; \
    --expression-attribute-values &#34;$SIZE_100&#34;

```

If we now query for the record then we will see our changes reflected. Here&#39;s a script I&#39;ve called **query.sh**, which you can use to verify changes at any point during this tutorial:

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

After the operations above, if you run **query.sh**, you should see this returned to you:

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
            &#34;Version&#34;: {
                &#34;N&#34;: &#34;2&#34;
            },
            &#34;Size&#34;: {
                &#34;S&#34;: &#34;200&#34;
            }
        }
    ],
    &#34;Count&#34;: 1,
    &#34;ScannedCount&#34;: 1,
    &#34;ConsumedCapacity&#34;: null
}

```

We can add a **condition-expression** to update only when our passed in condition is true. In our case, we want to both increment the version and make sure that the current version is what we assume it is:

```bash
SIZE_CURR_VERSION_TEMPLATE=$(cat &lt;&lt;EOF
{
    &#34;:size&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    },
    &#34;:curr_version&#34;: {
        &#34;N&#34;: &#34;%s&#34;
    },
    &#34;:new_version&#34;: {
        &#34;N&#34;: &#34;%s&#34;
    }
}
EOF
)

# update size to 200 if version is 1, also increment version to 2
SIZE_200=$(printf &#34;$SIZE_CURR_VERSION_TEMPLATE&#34; &#34;200&#34; &#34;1&#34; &#34;2&#34;)
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb update-item \
    --table-name Phones \
    --key &#34;$MOTO_COOL_KEY&#34; \
    --update-expression &#34;SET Size = :size, Version = :new_version&#34; \
    --condition-expression &#34;Version = :curr_version&#34; \
    --expression-attribute-values &#34;$SIZE_200&#34;

```

You should see this reflected if you query dynamo using the script above.

To prove that it actually fails when it should fail, we can try to set the size to 300, but only if the version is 1. If you ran the code from above you should see this fail:

```bash
# ..someone else is trying to update size to 300 if the version is 1, also trying to set to version 2, fails!
SIZE_300=$(printf &#34;$SIZE_CURR_VERSION_TEMPLATE&#34; &#34;300&#34; &#34;1&#34; &#34;2&#34;)
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb update-item \
    --table-name Phones \
    --key &#34;$MOTO_COOL_KEY&#34; \
    --update-expression &#34;SET Size = :size, Version = :new_version&#34; \
    --condition-expression &#34;Version = :curr_version&#34; \
    --expression-attribute-values &#34;$SIZE_300&#34;

```

Output:

```bash
An error occurred (ConditionalCheckFailedException) when calling the UpdateItem operation: The conditional request failed

```

If you run the query, you will also see that the size is still 200 while the version remains at 2.

You will notice that this **--condition-expression** is also a parameter option on the **put-item** operation, thus this pattern will work for the two most common operations against a dynamo item.
