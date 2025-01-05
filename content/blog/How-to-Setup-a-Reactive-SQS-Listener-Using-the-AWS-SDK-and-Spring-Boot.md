---
title: "How to Setup a Reactive SQS Listener Using the AWS SDK and Spring Boot"
date: 2020-09-12T21:42:52
draft: false
tags: [java, spring, aws, webflux]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/reactive-sqs).

Following up on the previous post where we showed [how to send SQS messages to Localstack using the AWS SDK for Java 2.0](https://nickolasfisher.com/blog/how-to-send-sqs-messages-to-localstack-with-the-aws-java-sdk-20), we will now demonstrate how to write code that continuously polls for SQS messages, processes them, then deletes them off the queue.

## The App

Building off of the work in the last post, where we had set up an **SqsAsyncClient** as a **Bean**:

```java
@Configuration
public class AwsSqsConfig {

    @Bean
    public SqsAsyncClient amazonSQSAsyncClient() {
        return SqsAsyncClient.builder()
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

And where we had also set up a local SQS queue in localstack with the CLI:

```bash
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

QUEUE_NAME="my-queue"

aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name "$QUEUE_NAME"

```

We can implement a simple SQS poller that will:

- Use long polling, to efficiently only pull messages in a xxx second window if there are messages available to be pulled
- Only poll if the previous poll has completed
- Delete the message off the queue after processing

The code that can do that can look like:

```java
@Component
public class SQSListenerBean {

    public static final Logger LOGGER = LoggerFactory.getLogger(SQSListenerBean.class);
    private final SqsAsyncClient sqsAsyncClient;
    private final String queueUrl;

    public SQSListenerBean(SqsAsyncClient sqsAsyncClient) {
        this.sqsAsyncClient = sqsAsyncClient;
        try {
            this.queueUrl = this.sqsAsyncClient.getQueueUrl(GetQueueUrlRequest.builder().queueName("my-queue").build()).get().queueUrl();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @PostConstruct
    public void continuousListener() {
        Mono<ReceiveMessageResponse> receiveMessageResponseMono = Mono.fromFuture(() ->
                sqsAsyncClient.receiveMessage(
                    ReceiveMessageRequest.builder()
                            .maxNumberOfMessages(5)
                            .queueUrl(queueUrl)
                            .waitTimeSeconds(10)
                            .visibilityTimeout(30)
                            .build()
                )
        );

        receiveMessageResponseMono
                .repeat()
                .retry()
                .map(ReceiveMessageResponse::messages)
                .map(Flux::fromIterable)
                .flatMap(messageFlux -> messageFlux)
                .subscribe(message -> {
                    LOGGER.info("message body: " + message.body());

                    sqsAsyncClient.deleteMessage(DeleteMessageRequest.builder().queueUrl(queueUrl).receiptHandle(message.receiptHandle()).build())
                        .thenAccept(deleteMessageResponse -> {
                            LOGGER.info("deleted message with handle " + message.receiptHandle());
                        });
                });
    }
}
```

In this case, the actual processing of the message is just a log message printing out the message body.

If you start up the app, and send a sample message to that queue with:

```bash
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

Q_URL=$(aws --endpoint-url http://localhost:4566 sqs get-queue-url --queue-name "my-queue" --output text)
aws --endpoint-url http://localhost:4566 sqs send-message --queue-url "$Q_URL" --message-body "hey there"

```

You will see the application print out something like:

```bash
INFO 17716 --- [c-response-0-21] c.n.reactivesqs.SQSListenerBean          : message body: hey there
INFO 17716 --- [c-response-0-22] c.n.reactivesqs.SQSListenerBean          : deleted message with handle hwwmv...buncha letters...

```

You could further tweak this to your heart's content.
