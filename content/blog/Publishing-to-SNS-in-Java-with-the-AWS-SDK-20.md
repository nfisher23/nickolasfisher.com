---
title: "Publishing to SNS in Java with the AWS SDK 2.0"
date: 2020-11-28T20:16:05
draft: false
tags: [java, spring, reactive, aws, webflux]
---

SNS is a medium to broadcast messages to multiple subscribers. A common use case is to have multiple SQS queues subscribing to the same SNS topic--this way, the _publishing_ application only needs to focus on events that are specific to its business use case, and _subscribing_ applications can configure an SQS queue and consume the event independently of other services. This helps organizations scale and significantly reduces the need to communicate between teams--each team can focus on its contract and business use case.

This article will show how to publish to an SNS topic with java, using the AWS SDK 2.0, which has full reactive support. The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

## Setup Infra

To start with, I'll leverage a previous article written which [sets up a subscription for an SQS queue on an SNS topic](https://nickolasfisher.com/blog/how-to-setup-sns-message-forwarding-to-sqs-with-the-aws-cli). There, we had a **docker-compose.yaml** file like:

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

And, our initializing script to setup the queue subscribing to the topic was:

```bash
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

QUEUE_NAME="my-queue"
TOPIC_NAME="my-topic"

QUEUE_URL=$(aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name "$QUEUE_NAME" --output text)
echo "queue url: $QUEUE_URL"

TOPIC_ARN=$(aws --endpoint-url http://localhost:4566 sns create-topic --output text --name "$TOPIC_NAME")
echo "topic arn: $TOPIC_ARN"

QUEUE_ARN=$(aws --endpoint-url http://localhost:4566 sqs get-queue-attributes --queue-url "$QUEUE_URL" | jq -r ".Attributes.QueueArn")
echo "queue arn: $QUEUE_ARN"

SUBSCRIPTION_ARN=$(aws --endpoint-url http://localhost:4566 sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$QUEUE_ARN" --output text)

# modify to raw message delivery true
aws --endpoint-url http://localhost:4566 sns set-subscription-attributes \
  --subscription-arn "$SUBSCRIPTION_ARN" --attribute-name RawMessageDelivery --attribute-value true

```

This configures an SQS queue named "my-queue" and an SNS topic named "my-topic". It then sets up a subscription for the queue on the topic with "raw message delivery" as true.

With this in place, we can start writing code. I will again leverage work done in a previous article about [setting up a reactive SQS listener in spring boot](https://nickolasfisher.com/blog/how-to-setup-a-reactive-sqs-listener-using-the-aws-sdk-and-spring-boot). To start with, we will add in a dependency for SNS \[note that this leverages the bill of materials spec in the maven pom, which is why there is no version specified here\]:

```xml
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>sns</artifactId>
</dependency>

```

This obviously imports the AWS library for SNS, which we can use to configure an sns client like so:

```java
@Configuration
public class AwsSnsConfig {

    @Bean
    public SnsAsyncClient amazonSNSAsyncClient() {
        return SnsAsyncClient.builder()
                .endpointOverride(URI.create("http://localhost:4566"))
                .region(Region.US_EAST_1)
                .credentialsProvider(StaticCredentialsProvider.create(new AwsCredentials() {
                    @Override
                    public String accessKeyId() {
                        return "FAKE";
                    }

                    @Override
                    public String secretAccessKey() {
                        return "FAKE";
                    }
                }))
                .build();
    }
}

```

Note that these match the access and secret key we used in the localstack initialization script. To finish this example off, we can create a **PostConstruct** initializing bean:

```java
@Component
public class SnsSenderBean {

    private final SnsAsyncClient snsAsyncClient;

    // ARN's are immutable. In reality, you'll want to pass this in as config per environment
    private static final String topicARN = "arn:aws:sns:us-east-1:000000000000:my-topic";

    public SnsSenderBean(SnsAsyncClient snsAsyncClient) {
        this.snsAsyncClient = snsAsyncClient;
    }

    @PostConstruct
    public void sendHelloToSNS() {
        Mono.fromFuture(() -> snsAsyncClient.publish(PublishRequest.builder().topicArn(topicARN).message("message-from-sns").build()))
                .repeat(3)
                .subscribe();
    }
}

```

This sends four identical messages to SNS with a body of "message-from-sns". These four messages will end up in the SQS queue, forwarded by SNS.

The SQS listener already configured will pick up these messages, write some logs, then delete them off the queue. My logs look like this:

```bash
c.n.reactivesqs.SQSListenerBean : message body: message-from-sns
c.n.reactivesqs.SQSListenerBean : message body: message-from-sns
c.n.reactivesqs.SQSListenerBean : deleted message with handle nejjaylz...
c.n.reactivesqs.SQSListenerBean : deleted message with handle ggpzrb....
c.n.reactivesqs.SQSListenerBean : message body: message-from-sns
c.n.reactivesqs.SQSListenerBean : deleted message with handle mgsaut....
c.n.reactivesqs.SQSListenerBean : message body: message-from-sns
c.n.reactivesqs.SQSListenerBean : deleted message with handle aouovw....

```

Remember to [check out the source code on github](https://github.com/nfisher23/reactive-programming-webflux).
