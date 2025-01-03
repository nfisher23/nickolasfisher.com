---
title: "How to Setup SNS Message Forwarding to SQS with the AWS CLI"
date: 2020-08-15T20:42:47
draft: false
tags: [distributed systems, DevOps, aws]
---

[Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/welcome.html) is AWS's solution to pub/sub. In a large, distributed system, decoupling _events_ from services that _need to act on those events_ allows for teams that own different services to better work in parallel, and also prevents the need for coordinating code deploys to deliver new features. If a services is already publishing a generic event, other services can hook into that event and act on them without needing anything but a bit of infrastructure.

Most commonly, you will want to use SNS with Amazon SQS. Multiple queues can subscribe to the same SNS topic, and with no filters setup, every event sent to the SNS topic will be forwarded to all the SQS queues for you automatically. I'm going to show you how to do that with the CLI using localstack in this post.

### Start localstack on your machine, configure CLI

I took the **docker-compose.yaml** from [the root of the localstack github repository](https://github.com/localstack/localstack/blob/master/docker-compose.yml):

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

Go ahead and copy paste that thing and run \[in the same directory\]:

```bash
docker-compose up -d

```

We can set some dummy environment variables to make localstack and the CLI happy:

```bash
export AWS_DEFAULT_REGION=us-west-2export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

```

You can test that your CLI is working with something like

```bash
aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name "test"

```

If all is well you'll see an output like:

```json
{
    "QueueUrls": [
        "http://localhost:4566/000000000000/test"
    ]
}

```

### Actually Do the Forwarding Now

We will first need to create both the SNS topic and the SQS queue (these are both idempotent operations):

```bash
QUEUE_NAME="my-queue"
TOPIC_NAME="my-topic"
aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name "$QUEUE_NAME" --output text
aws --endpoint-url http://localhost:4566 sns create-topic --output text --name "$TOPIC_NAME"

```

Creating the queue will by default return the queue url, and creating the SNS topic will by default return its ARN (Amazon Resource Name). It will make our lives easier if we store those as bash variables:

```bash
QUEUE_URL=$(aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name "$QUEUE_NAME" --output text)
TOPIC_ARN=$(aws --endpoint-url http://localhost:4566 sns create-topic --output text --name "$TOPIC_NAME")

```

To set up a subscription, we also are going to need to grab the SQS queue ARN. I will do that by leveraging [jq](https://stedolan.github.io/jq/manual/):

```bash
QUEUE_ARN=$(aws --endpoint-url http://localhost:4566 sqs get-queue-attributes --queue-url "$QUEUE_URL" | jq -r ".Attributes.QueueArn")

```

Finally, we will set up the link between the two \[and also grab the ARN of the subscription\] with:

```bash
SUBSCRIPTION_ARN=$(aws --endpoint-url http://localhost:4566 sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$QUEUE_ARN" --output text)

```

At this point we should be able to see our subscription in a list with:

```bash
aws --endpoint-url http://localhost:4566 sns list-subscriptions

```

The output from that should look something like:

```json
{
    "Subscriptions": [
        {
            "SubscriptionArn": "arn:aws:sns:us-east-1:000000000000:my-topic:0243d3b4-4cdd-41c8-abbf-d8f0f83a74c5",
            "Owner": "",
            "Protocol": "sqs",
            "Endpoint": "arn:aws:sqs:us-east-1:000000000000:my-queue",
            "TopicArn": "arn:aws:sns:us-east-1:000000000000:my-topic"
        }
    ]
}

```

And if we send a message to the SNS topic, we should be able to see a response by polling the SQS queue:

```bash
aws sns --endpoint-url http://localhost:4566 publish --topic-arn "$TOPIC_ARN" --message "hello!"
aws sqs --endpoint-url http://localhost:4566 receive-message --queue-url "$QUEUE_URL"

```

If you take a close look at the message as SQS receives it, you will see that the message was not delivered in its original form:

```json
{
    "Messages": [
        {
            "MessageId": "24810d56-1f40-0569-d5f9-751dbc881fcc",
            "ReceiptHandle": "chbhoztdlwckzmbjctnecnyafkfkdwzgonqetkwoxvvdxfohrmgplcsdgmskwiwhienohhefdrhmqxxjrqtuamoliwpfwzldugbloxrxjjnmpatswuoetnpoudjugphvgzywrzjexdvktenqiaxczofiphjstzslnygpdxwjsarlgiuhpeioohvav",
            "MD5OfBody": "e999e85bed5f7a06f9b5548304e9ea49",
            "Body": "{\"Type\": \"Notification\", \"MessageId\": \"6af3f1a1-07d5-4f16-b1d3-a3dc3656e107\", \"Token\": null, \"TopicArn\": \"arn:aws:sns:us-east-1:000000000000:my-topic\", \"Message\": \"hello!\", \"SubscribeURL\": null, \"Timestamp\": \"2020-08-22T22:27:45.235Z\", \"SignatureVersion\": \"1\", \"Signature\": \"EXAMPLEpH+..\", \"SigningCertURL\": \"https://sns.us-east-1.amazonaws.com/SimpleNotificationService-0000000000000000000000.pem\"}",
            "Attributes": {
                "SenderId": "AIDAIT2UOQQY3AUEKVGXU",
                "SentTimestamp": "1598135265266",
                "ApproximateReceiveCount": "1",
                "ApproximateFirstReceiveTimestamp": "1598135265910"
            }
        }
    ]
}

```

This is because **raw message delivery** is not **true** when you first create the subscription. You can change that with one more CLI command:

```bash
aws --endpoint-url http://localhost:4566 sns set-subscription-attributes \
  --subscription-arn "$SUBSCRIPTION_ARN" --attribute-name RawMessageDelivery --attribute-value true

```

Now when you ask for a message from SQS you will see it in its proper form:

```json
{
    "Messages": [
        {
            "MessageId": "e03aa463-61d2-3910-97ca-d0eb13274082",
            "ReceiptHandle": "tcjqhbygluhgeyjgqcahrxseqztnwlkppciqjoollvlavhruexvryomumruvrpkiykljcouekexunqijuswzccjzzclbbwreafvmusqnbtqdpclnzgwatxnxgwvegzsrwkzinpavmdekeqqwdvyktpibywifsbeognewqtibjjwnvdjrdwnbhujtn",
            "MD5OfBody": "5a8dd3ad0756a93ded72b823b19dd877",
            "Body": "hello!",
            "Attributes": {
                "SenderId": "AIDAIT2UOQQY3AUEKVGXU",
                "SentTimestamp": "1598135539742",
                "ApproximateReceiveCount": "1",
                "ApproximateFirstReceiveTimestamp": "1598135546283"
            }
        }
    ]
}

```

And you should be good to go.
