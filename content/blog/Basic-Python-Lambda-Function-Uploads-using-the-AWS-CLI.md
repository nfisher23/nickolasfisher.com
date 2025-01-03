---
title: "Basic Python Lambda Function Uploads using the AWS CLI"
date: 2021-02-06T21:07:12
draft: false
tags: [DevOps, aws, aws-lambda]
---

AWS Lambda functions were the first &#34;serverless&#34; way to run code. Of course, there are still servers, but the point is that you can nearly forget about managing those servers and all of that is owned by AWS.

Lambda functions are called functions because that&#39;s literally what you upload to AWS: a function that takes an **event** and **context**. The event will just be a JSON representation of something that happens on the system \[the structure of the event depends on what is invoking the lambda function\], and the context contains a bunch of metadata about the invocation that you usually don&#39;t really care about.

A simple lambda function \[that we&#39;ll be using in this article\] could look like this:

```python
import logging
import math
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    &#34;&#34;&#34;
    Politely respond with the same event
    &#34;&#34;&#34;
    logger.info(&#39;Event: %s&#39;, event)
    logger.info(&#39;context: %s&#39;, context.__dict__)

    event[&#39;hello&#39;] = &#34;well hello there&#34;
    return event

```

This function just logs the event and context, then adds a &#34;hello&#34; key to the event before echo-ing it back to whatever invokes it.

## Setup Localstack

Because it&#39;s much simpler to get started with \[no need to create an AWS account\] and because I don&#39;t want you spending money accidentally, we&#39;re going to use [localstack](https://github.com/localstack/localstack) to mock out our AWS interactions. Localstack supports lambdas in a variety of use cases quite well.

To setup your localstack infrastructure, which we&#39;ll just run as a container on your machine, you&#39;ll want docker and docker-compose installed. Then you can use this **docker-compose.yaml**:

```yaml
version: &#39;2.1&#39;

services:
  localstack:
    container_name: &#34;${LOCALSTACK_DOCKER_NAME-localstack_main}&#34;
    image: localstack/localstack
    ports:
      - &#34;4566-4599:4566-4599&#34;
      - &#34;${PORT_WEB_UI-8080}:${PORT_WEB_UI-8080}&#34;
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
      - &#34;${TMPDIR:-/tmp/localstack}:/tmp/localstack&#34;
      - &#34;/var/run/docker.sock:/var/run/docker.sock&#34;

```

Then simply navigate to where you&#39;ve placed the file in your filesystem and run:

```bash
$ docker-compose up

```

## Deploy and run our Python Lambda Function

To actually start using our lambda function now that we have our infrastructure and code ready, we will first need to create an IAM role to run the lambda, then attach a policy to that role to allow it to operate as a lambda. We could optionally create our own policy, but AWS has a bunch of policies ready for us to already use, and for this article we&#39;ll just reuse it:

```bash
# bunch of fake creds to make the cli happy
export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;
export AWS_DEFAULT_REGION=us-east-1

# create role, attach lambda policy to role
aws --endpoint-url http://localhost:4566 iam create-role --role-name lambda-python-ex --assume-role-policy-document file://trust-policy.json

aws --endpoint-url http://localhost:4566 iam attach-role-policy --role-name lambda-python-ex --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

```

And with that in place, we&#39;re just a few bash commands away from uploading and invoking our function. Assuming you have our lambda from earlier in a file called **my\_func.py**, the following will upload your lambda, invoke it, display the response, then show logs that were shipped to cloudwatch:

```bash
# you have to zip it up to upload it
zip my_func.zip my_func.py
aws --endpoint-url http://localhost:4566 lambda create-function --function-name my-python-function \
  --zip-file fileb://my_func.zip --handler my_func.lambda_handler --runtime python3.8 \
  --role arn:aws:iam::000000000000:role/lambda-python-ex

# invoke the lambda and save the result to a file
aws --endpoint-url http://localhost:4566 lambda invoke --function-name my-python-function --payload &#39;{&#34;first_name&#34;: &#34;jack&#34;, &#34;last_name&#34;: &#34;berry&#34;}&#39; response.json

# display the response from invoking the lambda
echo &#34;response from lambda&#34;
echo &#34;-------&#34;
cat response.json | json_pp
echo &#34;-------&#34;

# show some logs
FIRST_STREAM_NAME=$(aws --endpoint-url http://localhost:4566 logs describe-log-streams --log-group-name /aws/lambda/my-python-function | jq -r &#34;.logStreams[0].logStreamName&#34;)
aws --endpoint-url http://localhost:4566 logs get-log-events --log-group-name /aws/lambda/my-python-function --log-stream-name &#34;$FIRST_STREAM_NAME&#34; --limit 25 | jq -r &#34;.events | map(.message)[]&#34;

```

On my machine, this outputs:

```bash
updating: my_func.py (deflated 41%)
{
    &#34;FunctionName&#34;: &#34;my-python-function&#34;,
    &#34;FunctionArn&#34;: &#34;arn:aws:lambda:us-east-1:000000000000:function:my-python-function&#34;,
    &#34;Runtime&#34;: &#34;python3.8&#34;,
    &#34;Role&#34;: &#34;arn:aws:iam::000000000000:role/lambda-python-ex&#34;,
    &#34;Handler&#34;: &#34;my_func.lambda_handler&#34;,
    &#34;CodeSize&#34;: 368,
    &#34;Description&#34;: &#34;&#34;,
    &#34;Timeout&#34;: 3,
    &#34;LastModified&#34;: &#34;2021-02-13T22:14:50.861&#43;0000&#34;,
    &#34;CodeSha256&#34;: &#34;g9IeN8RAA49Qeu49SpVFfscd0dpML3z0NFNCYvOw9dI=&#34;,
    &#34;Version&#34;: &#34;$LATEST&#34;,
    &#34;VpcConfig&#34;: {},
    &#34;TracingConfig&#34;: {
        &#34;Mode&#34;: &#34;PassThrough&#34;
    },
    &#34;RevisionId&#34;: &#34;bbdd6125-d76b-4270-97c5-2f8c34d8f94c&#34;,
    &#34;State&#34;: &#34;Active&#34;,
    &#34;LastUpdateStatus&#34;: &#34;Successful&#34;
}
{
    &#34;StatusCode&#34;: 200,
    &#34;LogResult&#34;: &#34;&#34;,
    &#34;ExecutedVersion&#34;: &#34;$LATEST&#34;
}
response from lambda
-------
{
   &#34;last_name&#34; : &#34;berry&#34;,
   &#34;hello&#34; : &#34;well hello there&#34;,
   &#34;first_name&#34; : &#34;jack&#34;
}
-------
START RequestId: d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5 Version: $LATEST

[INFO]  2021-02-13T22:14:52.552Z        d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5    Event: {&#39;first_name&#39;: &#39;jack&#39;, &#39;last_name&#39;: &#39;berry&#39;}
[INFO]  2021-02-13T22:14:52.552Z        d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5    context: {&#39;aws_request_id&#39;: &#39;d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5&#39;, &#39;log_group_name&#39;: &#39;/aws/lambda/my-python-function&#39;, &#39;log_stream_name&#39;: &#39;2021/02/13/[$LATEST]016f3b4e250d5d1a10426f2b48e41a6a&#39;, &#39;function_name&#39;: &#39;my-python-function&#39;, &#39;memory_limit_in_mb&#39;: &#39;1536&#39;, &#39;function_version&#39;: &#39;$LATEST&#39;, &#39;invoked_function_arn&#39;: &#39;arn:aws:lambda:us-east-1:000000000000:function:my-python-function&#39;, &#39;client_context&#39;: None, &#39;identity&#39;: &lt;__main__.CognitoIdentity object at 0x7f00224ad490&gt;, &#39;_epoch_deadline_time_in_ms&#39;: 1613254495363}
END RequestId: d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5

REPORT RequestId: d9c9acaf-bb83-1dd5-16a4-46e92c9f13b5  Init Duration: 283.11 ms        Duration: 4.64 ms       Billed Duration: 5 ms   Memory Size: 1536 MB    Max Memory Used: 24 MB

```

Note that you can optionall delete your lambda function and clean up your logs like so:

```bash
# delete function, logs for cleanliness
aws --endpoint-url http://localhost:4566 logs delete-log-group --log-group-name $(aws --endpoint-url http://localhost:4566 logs describe-log-groups | jq -r &#34;.logGroups[0].logGroupName&#34;)
aws --endpoint-url http://localhost:4566 lambda delete-function --function-name my-python-function

```

And with that, you should be in a good place to start tinkering with this locally
