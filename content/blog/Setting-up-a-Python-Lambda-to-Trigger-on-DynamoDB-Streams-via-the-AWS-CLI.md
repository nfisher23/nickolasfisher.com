---
title: "Setting up a Python Lambda to Trigger on DynamoDB Streams via the AWS CLI"
date: 2021-02-07T19:47:50
draft: false
tags: [DevOps, aws, dynamodb, aws-lambda]
---

DynamoDB streams record information about what has changed in a DynamoDB table, and AWS lambdas are ways to run code without managing servers yourself. DynamoDB streams also have an integration with AWS Lambdas so that any change to a DynamoDB table can be processed by an AWS Lambda--still without worrying about keeping your servers up or maintaining them. That is the subject of this post.

We'll be using [localstack](https://github.com/localstack/localstack) to prove this out. You can follow along with previous blog posts \[like this one about [python lambdas and localstack](https://nickolasfisher.com/blog/basic-python-lambda-function-uploads-using-the-aws-cli)\] of mine for how to do AWS stuff with localstack.

**Important Note:** Localstack has a bug, which they claim to have fixed, where lambdas invoked inside the localstack container can't call other localstack resources, like sns or s3. I was able to hack around this and will cover the hack towards the end of this article. If you need to call other AWS resources with your lambda \[as will very often be the case\], then to really test it you'll just have to bite the bullet and use AWS itself as of now.

## Create AWS Resources and Lamdba

Assuming you already understand how to get localstack up and running locally, we'll need to create a dynamo table to work with:

```bash
# fake credentials to make the cli happy
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

# create simple table in localstack, streams enabled
aws --endpoint-url http://localhost:4566 --region=us-east-1 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name SampleTable \
  --attribute-definitions AttributeName=SamplePartitionKey,AttributeType=S \
  --key-schema AttributeName=SamplePartitionKey,KeyType=HASH \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_IMAGE

```

Note that streams are enabled and that we've configured it to have a stream specification of **NEW\_IMAGE**, which \[surprise\] emits stream records as the newly changed/created object.

We will also need to create an IAM role for our lambda function to assume when it runs, then attach a policy to that role which allows it to be a lambda--this includes logging so that we can observe it via cloudwatch and, in this case, we need to be able to interact with DynamoDB streams:

```bash
aws --region us-east-1 --endpoint-url http://localhost:4566 iam create-role --role-name SampleDynamoLambdaRole \
    --path "/service-role/" \
    --assume-role-policy-document file://trust-relationship.json

aws --region us-east-1 --endpoint-url http://localhost:4566 iam put-role-policy --role-name SampleDynamoLambdaRole \
    --policy-name SampleDynamoLambdaRolePolicy \
    --policy-document file://role-policy.json

```

Note that the **trust-relationship.json** looks like this:

```json
{
   "Version": "2021-01-01",
   "Statement": [
     {
       "Effect": "Allow",
       "Principal": {
         "Service": "lambda.amazonaws.com"
       },
       "Action": "sts:AssumeRole"
     }
   ]
}

```

And **role-policy.json** looks like:

```json
{
    "Version": "2021-01-01",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:us-east-1:0000000000:function:ddb_stream_listener*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:us-east-1:0000000000:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:DescribeStream",
                "dynamodb:GetRecords",
                "dynamodb:GetShardIterator",
                "dynamodb:ListStreams"
            ],
            "Resource": "arn:aws:dynamodb:us-east-1:0000000000:table/SampleTable/stream/*"
        }
    ]
}

```

Now we'll just create a python lambda that simply logs the event \[a DynamoDB stream record event\] and the context that it receives:

```python
import logging
import math
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Politely say hello
    """
    logger.info('Event: %s', event)
    logger.info('context: %s', context.__dict__)

    return event

```

With a little bit of bash and jq, we can finish this out like so:

```bash
zip my_func.zip my_func.py
aws --endpoint-url http://localhost:4566 lambda create-function --function-name ddb-lambda-function \
  --zip-file fileb://my_func.zip --handler my_func.lambda_handler --runtime python3.8 \
  --role arn:aws:iam::000000000000:role/SampleDynamoLambdaRole

STREAM_ARN=$(aws --endpoint-url http://localhost:4566 dynamodbstreams list-streams --table-name SampleTable | jq -r '.Streams[0] | .StreamArn')

aws --endpoint-url http://localhost:4566 lambda create-event-source-mapping \
    --region us-east-1 \
    --function-name ddb-lambda-function \
    --event-source "$STREAM_ARN"  \
    --batch-size 1 \
    --starting-position TRIM_HORIZON

```

We can test this by put-ing an item into Dynamo and viewing the logs of the lambda:

```bash
TEMPLATE=$(cat <<'EOF'
{
    "SamplePartitionKey": {
        "S": "%s"
    },
    "SampleValue": {
        "S": "%s"
    }
}
EOF
)

put_dynamo_local() {
    ITEM="$1"
    aws --endpoint-url http://localhost:4566 --region=us-east-1 dynamodb put-item \
      --table-name SampleTable \
      --item "$ITEM"
}

RANDOM_ITEM=$(printf "$TEMPLATE" "Random $RANDOM" "garf")
echo $RANDOM_ITEM

put_dynamo_local "$RANDOM_ITEM"

echo "sleeping"
sleep 1

# show some logs
FIRST_STREAM_NAME=$(aws --endpoint-url http://localhost:4566 logs describe-log-streams --log-group-name /aws/lambda/ddb-lambda-function | jq -r ".logStreams[0].logStreamName")
aws --endpoint-url http://localhost:4566 logs get-log-events --log-group-name /aws/lambda/ddb-lambda-function --log-stream-name "$FIRST_STREAM_NAME" --limit 50 | jq -r ".events | map(.message)[]"

```

And that should put you in pretty good shape

## A caveat: connection timeouts with localstack

That lambda isn't particularly useful, however. If you wanted to, for example, publish an SNS event on inserting a new item into a DynamoDB stream, even after modifying the policy attached to the lambda, this gets a connection timeout for me locally \[note that I'm running linux mint on my machine, YMMV\]:

```python
import logging
import math
import json
import boto3
import os
from botocore.client import Config
import boto3

config = Config(connect_timeout=3, retries={'max_attempts': 0})
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

sns_client = boto3.client('sns',
    endpoint_url="http://" + os.getenv("LOCALSTACK_HOSTNAME") + ":4566", # this is the actual docker container ip, and it fails.
    # endpoint_url="http://172.30.0.1:4566",  # this is the harcoded gateway ip for the network, and it succeeds
    config=config, region_name='us-east-1',
    aws_access_key_id="FAKE",
    aws_secret_access_key="FAKE")

def lambda_handler(event, context):
    logger.info('Event: %s', event)
    logger.info('context: %s', context.__dict__)

    return sns_client.list_topics()

```

As that comment indicates, if I take the docker compose network gateway ip address and put it in place of the **LOCALSTACK\_HOSTNAME** environment variable, then I can get it to publish successfully. My recommendation is to use real AWS resources and leverage terraform/s3 for environment promotion and versioning if you're doing this for anything other than a pet project. This, however, was a good learning exercise.
