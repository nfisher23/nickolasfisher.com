---
title: "Basic Python Lambda Function Uploads using the AWS CLI"
date: 2021-02-06T21:07:12
draft: false
tags: [DevOps, aws, aws-lambda]
---

AWS Lambda functions were the first "serverless" way to run code. Of course, there are still servers, but the point is that you can nearly forget about managing those servers and all of that is owned by AWS.

Lambda functions are called functions because that's literally what you upload to AWS: a function that takes an **event** and **context**. The event will just be a JSON representation of something that happens on the system \[the structure of the event depends on what is invoking the lambda function\], and the context contains a bunch of metadata about the invocation that you usually don't really care about.

A simple lambda function \[that we'll be using in this article\] could look like this:

```python
import logging
import math
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Politely respond with the same event
    """
    logger.info('Event: %s', event)
    logger.info('context: %s', context.__dict__)

    event['hello'] = "well hello there"
    return event

```

This function just logs the event and context, then adds a "hello" key to the event before echo-ing it back to whatever invokes it.

## Setup Localstack

Because it's much simpler to get started with \[no need to create an AWS account\] and because I don't want you spending money accidentally, we're going to use [localstack](https://github.com/localstack/localstack) to mock out our AWS interactions. Localstack supports lambdas in a variety of use cases quite well.

To setup your localstack infrastructure, which we'll just run as a container on your machine, you'll want docker and docker-compose installed. Then you can use this **docker-compose.yaml**:

```yaml
version: '2.1'

services:
  localstack:
    container_name: "${LOCALSTACK_DOCKER_NAME-localstack_main}"
    image: localstack/localstack
    ports:
      - "4566-4599:4566-4599"
      - "${PORT_WEB_UI-8080}:${PORT_WEB_UI-8080}"
    environment:
      - SERVICES=${SERVICES- }
      - DEBUG=${DEBUG- }
      - DATA_DIR=${DATA_DIR- }
      - PORT_WEB_UI=${PORT_WEB_UI- }
      - LAMBDA_EXECUTOR=${LAMBDA_EXECUTOR- }
      - KINESIS_ERROR_PROBABILITY=${KINESIS_ERROR_PROBABILITY- }
      - DOCKER_HOST=unix:///var/run/docker.sock
      - HOST_TMP_FOLDER=${TMPDIR}
    volumes:
      - "${TMPDIR:-/tmp/localstack}:/tmp/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"

```

Then simply navigate to where you've placed the file in your filesystem and run:

```bash
$ docker-compose up

```

## Deploy and run our Python Lambda Function

To actually start using our lambda function now that we have our infrastructure and code ready, we will first need to create an IAM role to run the lambda, then attach a policy to that role to allow it to operate as a lambda. We could optionally create our own policy, but AWS has a bunch of policies ready for us to already use, and for this article we'll just reuse it:

```bash
# bunch of fake creds to make the cli happy
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

# create role, attach lambda policy to role
aws --endpoint-url http://localhost:4566 iam create-role --role-name lambda-python-ex --assume-role-policy-document file://trust-policy.json

aws --endpoint-url http://localhost:4566 iam attach-role-policy --role-name lambda-python-ex --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

```

And with that in place, we're just a few bash commands away from uploading and invoking our function. Assuming you have our lambda from earlier in a file called **my\_func.py**, the following will upload your lambda, invoke it, display the response, then show logs that were shipped to cloudwatch:

```bash
# you have to zip it up to upload it
zip my_func.zip my_func.py
aws --endpoint-url http://localhost:4566 lambda create-function --function-name my-python-function \
  --zip-file fileb://my_func.zip --handler my_func.lambda_handler --runtime python3.8 \
  --role arn:aws:iam::000000000000:role/lambda-python-ex

# invoke the lambda and save the result to a file
aws --endpoint-url http://localhost:4566 lambda invoke --function-name my-python-function --payload '{"first_name": "jack", "last_name": "berry"}' response.json

# display the response from invoking the lambda
echo "response from lambda"
echo "-------"
cat response.json | json_pp
echo "-------"

# show some logs
FIRST_STREAM_NAME=$(aws --endpoint-url http://localhost:4566 logs describe-log-streams --log-group-name /aws/lambda/my-python-function | jq -r ".logStreams[0].logStreamName")
aws --endpoint-url http://localhost:4566 logs get-log-events --log-group-name /aws/lambda/my-python-function --log-stream-name "$FIRST_STREAM_NAME" --limit 25 | jq -r ".events | map(.message)[]"

```

On my machine, this outputs:

```bash
updating: my_func.py (deflated 41%)
{
    "FunctionName": "my-python-function",
    "FunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:my-python-function",
    "Runtime": "python3.8",
    "Role": "arn:aws:iam::000000000000:role/lambda-python-ex",
    "Handler": "my_func.lambda_handler",
    "CodeSize": 368,
    "Description": "",
    "Timeout": 3,
    "LastModified": "2021-02-13T22:14:50.861+0000",
    "CodeSha256": "g9IeN8RAA49Qeu49SpVFfscd0dpML3z0NFNCYvOw9dI=",
    "Version": "$LATEST",
    "VpcConfig": {},
    "TracingConfig": {
        "Mode": "PassThrough"
    },
    "RevisionId": "bbdd6125-d76b-4270-97c5-2f8c34d8f94c",
    "State": "Active",
    "LastUpdateStatus": "Successful"
}
{
    "StatusCode": 200,
    "LogResult": "",
    "ExecutedVersion": "$LATEST"
}
response from lambda
-------
{
   "last_name" : "berry",
   "hello" : "well hello there",
   "first_name" : "jack"
}
-------
START RequestId: d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5 Version: $LATEST

[INFO]  2021-02-13T22:14:52.552Z        d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5    Event: {'first_name': 'jack', 'last_name': 'berry'}
[INFO]  2021-02-13T22:14:52.552Z        d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5    context: {'aws_request_id': 'd9c9acaf-bb83-1dd5-16a4-46e92c9f13b5', 'log_group_name': '/aws/lambda/my-python-function', 'log_stream_name': '2021/02/13/[$LATEST]016f3b4e250d5d1a10426f2b48e41a6a', 'function_name': 'my-python-function', 'memory_limit_in_mb': '1536', 'function_version': '$LATEST', 'invoked_function_arn': 'arn:aws:lambda:us-east-1:000000000000:function:my-python-function', 'client_context': None, 'identity': <__main__.CognitoIdentity object at 0x7f00224ad490>, '_epoch_deadline_time_in_ms': 1613254495363}
END RequestId: d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5

REPORT RequestId: d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5  Init Duration: 283.11 ms        Duration: 4.64 ms       Billed Duration: 5 ms   Memory Size: 1536 MB    Max Memory Used: 24 MB

```

Note that you can optionall delete your lambda function and clean up your logs like so:

```bash
# delete function, logs for cleanliness
aws --endpoint-url http://localhost:4566 logs delete-log-group --log-group-name $(aws --endpoint-url http://localhost:4566 logs describe-log-groups | jq -r ".logGroups[0].logGroupName")
aws --endpoint-url http://localhost:4566 lambda delete-function --function-name my-python-function

```

And with that, you should be in a good place to start tinkering with this locally
