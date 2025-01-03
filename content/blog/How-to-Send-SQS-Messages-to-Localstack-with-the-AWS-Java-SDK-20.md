---
title: "How to Send SQS Messages to Localstack with the AWS Java SDK 2.0"
date: 2020-09-12T20:54:13
draft: false
tags: [java, reactive, aws, webflux]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/blob/master/README.md).

The completely rewritten [AWS SDK for Java 2.0](https://docs.aws.amazon.com/sdk-for-java/v2/developer-guide/welcome.html) comes with full reactive programming support all the way down. I wanted a way to test it out without spending any more or being at risk of spending too much money, so I used [localstack](https://github.com/localstack/localstack). This post is largely walking you through what I came up with.

## The Infra

To start with, you will want to ensure you have docker and docker-compose installed. Then you can [copy the localstack docker-compose file from the github repo](https://github.com/localstack/localstack/blob/master/docker-compose.yml) into your own **docker-compose.yaml** file like so:

```yaml>version: '2.1'

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

</code></pre>

<p>Navigate to the directory where that file lives and run:</p>

<pre><code class=
docker-compose up -d

```

Now that we have a local AWS clone running, let's create a queue for us to use with the aws cli:

```bash

export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

QUEUE_NAME="my-queue"

aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name "$QUEUE_NAME"

```

## The Application Now

Create a spring boot project \[e.g. use the spring initializr\]. You will want to make your **pom.xml** includes a similar **dependencyManagement** section as well as the aws sqs sdk:

```xml
...metadata...

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>software.amazon.awssdk</groupId>
                <artifactId>bom</artifactId>
                <version>2.5.5</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <properties>
        <java.version>11</java.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-webflux</artifactId>
        </dependency>

        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>sqs</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
            <exclusions>
                <exclusion>
                    <groupId>org.junit.vintage</groupId>
                    <artifactId>junit-vintage-engine</artifactId>
                </exclusion>
            </exclusions>
        </dependency>
        <dependency>
            <groupId>io.projectreactor</groupId>
            <artifactId>reactor-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>

</project>

```

With that, we need to configure our **SqsClient** to communicate with local. We can do that with something like:

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

And once we have our sqs client set up, actually sending a message is pretty straightforward. I included here a **PostConstruct** that will send of six messages right at application start up:

```java
@Component
public class SQSSenderBean {

    private Logger LOG = LoggerFactory.getLogger(SQSSenderBean.class);

    private final SqsAsyncClient sqsAsyncClient;

    public SQSSenderBean(SqsAsyncClient sqsAsyncClient) {
        this.sqsAsyncClient = sqsAsyncClient;
    }

    @PostConstruct
    public void sendHelloMessage() throws Exception {
        LOG.info("hello!!!");
        CompletableFuture wat = sqsAsyncClient.getQueueUrl(GetQueueUrlRequest.builder().queueName("my-queue").build());
        GetQueueUrlResponse getQueueUrlResponse = wat.get();

        Mono.fromFuture(() -> sqsAsyncClient.sendMessage(
                SendMessageRequest.builder()
                        .queueUrl(getQueueUrlResponse.queueUrl())
                        .messageBody("new message at second " + ZonedDateTime.now().getSecond())
                        .build()
            ))
                .retryWhen(Retry.max(3))
                .repeat(5)
                .subscribe();
    }
}

```

If you start up the application, then use the CLI to get a message off the queue:

```java
export AWS_SECRET_ACCESS_KEY="FAKE"
export AWS_ACCESS_KEY_ID="FAKE"
export AWS_DEFAULT_REGION=us-east-1

Q_URL=$(aws --endpoint-url http://localhost:4566 sqs get-queue-url --queue-name "my-queue" --output text)
aws --endpoint-url http://localhost:4566 sqs receive-message --queue-url "$Q_URL"

```

You should see something like:

```json
{
    "Messages": [
        {
            "MessageId": "5fef529f-8787-d931-b2f6-34127ae978cd",
            "ReceiptHandle": "duytrocbgdfbfnyiqpsvnsqroimuegaigttaueclycefoxfwtlwvnykealgmvybwnckqjjgyoedzsmxulazjcyqdhaalwztyddxkssqhqycqctxhfhavmyylvpybljldflzavfghwwjdlgyvfbiprwrirappaocctdcqzilufjoobllvekbinirmt",
            "MD5OfBody": "08550418f58bc838c192dc825693e5a6",
            "Body": "new message at second 30",
            "Attributes": {
                "SenderId": "AIDAIT2UOQQY3AUEKVGXU",
                "SentTimestamp": "1600551210970",
                "ApproximateReceiveCount": "1",
                "ApproximateFirstReceiveTimestamp": "1600551215120"
            }
        }
    ]
}

```

And you should be good to go
