---
title: "Setting up a Python Lambda to Trigger on DynamoDB Streams via the AWS CLI"
date: 2021-02-07T19:47:50
draft: false
tags: [DevOps, aws, dynamodb, aws-lambda]
---

DynamoDB streams record information about what has changed in a DynamoDB table, and AWS lambdas are ways to run code without managing servers yourself. DynamoDB streams also have an integration with AWS Lambdas so that any change to a DynamoDB table can be processed by an AWS Lambda--still without worrying about keeping your servers up or maintaining them. That is the subject of this post.

We&#39;ll be using [localstack](https://github.com/localstack/localstack) to prove this out. You can follow along with previous blog posts \[like this one about [python lambdas and localstack](https://nickolasfisher.com/blog/Basic-Python-Lambda-Function-Uploads-using-the-AWS-CLI)\] of mine for how to do AWS stuff with localstack.

**Important Note:** Localstack has a bug, which they claim to have fixed, where lambdas invoked inside the localstack container can&#39;t call other localstack resources, like sns or s3. I was able to hack around this and will cover the hack towards the end of this article. If you need to call other AWS resources with your lambda \[as will very often be the case\], then to really test it you&#39;ll just have to bite the bullet and use AWS itself as of now.

## Create AWS Resources and Lamdba

Assuming you already understand how to get localstack up and running locally, we&#39;ll need to create a dynamo table to work with:

```bash
# fake credentials to make the cli happy
export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;
export AWS_DEFAULT_REGION=us-east-1

# create simple table in localstack, streams enabled
aws --endpoint-url http://localhost:4566 --region=us-east-1 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name SampleTable \
  --attribute-definitions AttributeName=SamplePartitionKey,AttributeType=S \
  --key-schema AttributeName=SamplePartitionKey,KeyType=HASH \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_IMAGE

```

Note that streams are enabled and that we&#39;ve configured it to have a stream specification of **NEW\_IMAGE**, which \[surprise\] emits stream records as the newly changed/created object.

We will also need to create an IAM role for our lambda function to assume when it runs, then attach a policy to that role which allows it to be a lambda--this includes logging so that we can observe it via cloudwatch and, in this case, we need to be able to interact with DynamoDB streams:

```bash
aws --region us-east-1 --endpoint-url http://localhost:4566 iam create-role --role-name SampleDynamoLambdaRole \
    --path &#34;/service-role/&#34; \
    --assume-role-policy-document file://trust-relationship.json

aws --region us-east-1 --endpoint-url http://localhost:4566 iam put-role-policy --role-name SampleDynamoLambdaRole \
    --policy-name SampleDynamoLambdaRolePolicy \
    --policy-document file://role-policy.json

```

Note that the **trust-relationship.json** looks like this:

```json
{
   &#34;Version&#34;: &#34;2021-01-01&#34;,
   &#34;Statement&#34;: [
     {
       &#34;Effect&#34;: &#34;Allow&#34;,
       &#34;Principal&#34;: {
         &#34;Service&#34;: &#34;lambda.amazonaws.com&#34;
       },
       &#34;Action&#34;: &#34;sts:AssumeRole&#34;
     }
   ]
}

```

And **role-policy.json** looks like:

```json
{
    &#34;Version&#34;: &#34;2021-01-01&#34;,
    &#34;Statement&#34;: [
        {
            &#34;Effect&#34;: &#34;Allow&#34;,
            &#34;Action&#34;: &#34;lambda:InvokeFunction&#34;,
            &#34;Resource&#34;: &#34;arn:aws:lambda:us-east-1:0000000000:function:ddb_stream_listener*&#34;
        },
        {
            &#34;Effect&#34;: &#34;Allow&#34;,
            &#34;Action&#34;: [
                &#34;logs:CreateLogGroup&#34;,
                &#34;logs:CreateLogStream&#34;,
                &#34;logs:PutLogEvents&#34;
            ],
            &#34;Resource&#34;: &#34;arn:aws:logs:us-east-1:0000000000:*&#34;
        },
        {
            &#34;Effect&#34;: &#34;Allow&#34;,
            &#34;Action&#34;: [
                &#34;dynamodb:DescribeStream&#34;,
                &#34;dynamodb:GetRecords&#34;,
                &#34;dynamodb:GetShardIterator&#34;,
                &#34;dynamodb:ListStreams&#34;
            ],
            &#34;Resource&#34;: &#34;arn:aws:dynamodb:us-east-1:0000000000:table/SampleTable/stream/*&#34;
        }
    ]
}

```

Now we&#39;ll just create a python lambda that simply logs the event \[a DynamoDB stream record event\] and the context that it receives:

```python
import logging
import math
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    &#34;&#34;&#34;
    Politely say hello
    &#34;&#34;&#34;
    logger.info(&#39;Event: %s&#39;, event)
    logger.info(&#39;context: %s&#39;, context.__dict__)

    return event

```

With a little bit of bash and jq, we can finish this out like so:

```bash
zip my_func.zip my_func.py
aws --endpoint-url http://localhost:4566 lambda create-function --function-name ddb-lambda-function \
  --zip-file fileb://my_func.zip --handler my_func.lambda_handler --runtime python3.8 \
  --role arn:aws:iam::000000000000:role/SampleDynamoLambdaRole

STREAM_ARN=$(aws --endpoint-url http://localhost:4566 dynamodbstreams list-streams --table-name SampleTable | jq -r &#39;.Streams[0] | .StreamArn&#39;)

aws --endpoint-url http://localhost:4566 lambda create-event-source-mapping \
    --region us-east-1 \
    --function-name ddb-lambda-function \
    --event-source &#34;$STREAM_ARN&#34;  \
    --batch-size 1 \
    --starting-position TRIM_HORIZON

```

We can test this by put-ing an item into Dynamo and viewing the logs of the lambda:

```bash
TEMPLATE=$(cat &lt;&lt;&#39;EOF&#39;
{
    &#34;SamplePartitionKey&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    },
    &#34;SampleValue&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    }
}
EOF
)

put_dynamo_local() {
    ITEM=&#34;$1&#34;
    aws --endpoint-url http://localhost:4566 --region=us-east-1 dynamodb put-item \
      --table-name SampleTable \
      --item &#34;$ITEM&#34;
}

RANDOM_ITEM=$(printf &#34;$TEMPLATE&#34; &#34;Random $RANDOM&#34; &#34;garf&#34;)
echo $RANDOM_ITEM

put_dynamo_local &#34;$RANDOM_ITEM&#34;

echo &#34;sleeping&#34;
sleep 1

# show some logs
FIRST_STREAM_NAME=$(aws --endpoint-url http://localhost:4566 logs describe-log-streams --log-group-name /aws/lambda/ddb-lambda-function | jq -r &#34;.logStreams[0].logStreamName&#34;)
aws --endpoint-url http://localhost:4566 logs get-log-events --log-group-name /aws/lambda/ddb-lambda-function --log-stream-name &#34;$FIRST_STREAM_NAME&#34; --limit 50 | jq -r &#34;.events | map(.message)[]&#34;

```

And that should put you in pretty good shape

## A caveat: connection timeouts with localstack

That lambda isn&#39;t particularly useful, however. If you wanted to, for example, publish an SNS event on inserting a new item into a DynamoDB stream, even after modifying the policy attached to the lambda, this gets a connection timeout for me locally \[note that I&#39;m running linux mint on my machine, YMMV\]:

```python
import logging
import math
import json
import boto3
import os
from botocore.client import Config
import boto3

config = Config(connect_timeout=3, retries={&#39;max_attempts&#39;: 0})
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

sns_client = boto3.client(&#39;sns&#39;,
    endpoint_url=&#34;http://&#34; &#43; os.getenv(&#34;LOCALSTACK_HOSTNAME&#34;) &#43; &#34;:4566&#34;, # this is the actual docker container ip, and it fails.
    # endpoint_url=&#34;http://172.30.0.1:4566&#34;,  # this is the harcoded gateway ip for the network, and it succeeds
    config=config, region_name=&#39;us-east-1&#39;,
    aws_access_key_id=&#34;FAKE&#34;,
    aws_secret_access_key=&#34;FAKE&#34;)

def lambda_handler(event, context):
    logger.info(&#39;Event: %s&#39;, event)
    logger.info(&#39;context: %s&#39;, context.__dict__)

    return sns_client.list_topics()

```

As that comment indicates, if I take the docker compose network gateway ip address and put it in place of the **LOCALSTACK\_HOSTNAME** environment variable, then I can get it to publish successfully. My recommendation is to use real AWS resources and leverage terraform/s3 for environment promotion and versioning if you&#39;re doing this for anything other than a pet project. This, however, was a good learning exercise.
