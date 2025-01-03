---
title: "Publishing to SNS in Java with the AWS SDK 2.0"
date: 2020-11-01T00:00:00
draft: false
---

SNS is a medium to broadcast messages to multiple subscribers. A common use case is to have multiple SQS queues subscribing to the same SNS topic--this way, the _publishing_ application only needs to focus on events that are specific to its business use case, and _subscribing_ applications can configure an SQS queue and consume the event independently of other services. This helps organizations scale and significantly reduces the need to communicate between teams--each team can focus on its contract and business use case.

This article will show how to publish to an SNS topic with java, using the AWS SDK 2.0, which has full reactive support. The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

## Setup Infra

To start with, I&#39;ll leverage a previous article written which [sets up a subscription for an SQS queue on an SNS topic](https://nickolasfisher.com/blog/How-to-Setup-SNS-Message-Forwarding-to-SQS-with-the-AWS-CLI). There, we had a **docker-compose.yaml** file like:

``` yaml
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

And, our initializing script to setup the queue subscribing to the topic was:

``` bash
export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;
export AWS_DEFAULT_REGION=us-east-1

QUEUE_NAME=&#34;my-queue&#34;
TOPIC_NAME=&#34;my-topic&#34;

QUEUE_URL=$(aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name &#34;$QUEUE_NAME&#34; --output text)
echo &#34;queue url: $QUEUE_URL&#34;

TOPIC_ARN=$(aws --endpoint-url http://localhost:4566 sns create-topic --output text --name &#34;$TOPIC_NAME&#34;)
echo &#34;topic arn: $TOPIC_ARN&#34;

QUEUE_ARN=$(aws --endpoint-url http://localhost:4566 sqs get-queue-attributes --queue-url &#34;$QUEUE_URL&#34; | jq -r &#34;.Attributes.QueueArn&#34;)
echo &#34;queue arn: $QUEUE_ARN&#34;

SUBSCRIPTION_ARN=$(aws --endpoint-url http://localhost:4566 sns subscribe --topic-arn &#34;$TOPIC_ARN&#34; --protocol sqs --notification-endpoint &#34;$QUEUE_ARN&#34; --output text)

