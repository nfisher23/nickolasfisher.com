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

```yaml&gt;version: &#39;2.1&#39;

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

&lt;/code&gt;&lt;/pre&gt;

&lt;p&gt;Navigate to the directory where that file lives and run:&lt;/p&gt;

&lt;pre&gt;&lt;code class=
docker-compose up -d

```

Now that we have a local AWS clone running, let&#39;s create a queue for us to use with the aws cli:

```bash

export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;
export AWS_DEFAULT_REGION=us-east-1

QUEUE_NAME=&#34;my-queue&#34;

aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name &#34;$QUEUE_NAME&#34;

```

## The Application Now

Create a spring boot project \[e.g. use the spring initializr\]. You will want to make your **pom.xml** includes a similar **dependencyManagement** section as well as the aws sqs sdk:

```xml
...metadata...

    &lt;dependencyManagement&gt;
        &lt;dependencies&gt;
            &lt;dependency&gt;
                &lt;groupId&gt;software.amazon.awssdk&lt;/groupId&gt;
                &lt;artifactId&gt;bom&lt;/artifactId&gt;
                &lt;version&gt;2.5.5&lt;/version&gt;
                &lt;type&gt;pom&lt;/type&gt;
                &lt;scope&gt;import&lt;/scope&gt;
            &lt;/dependency&gt;
        &lt;/dependencies&gt;
    &lt;/dependencyManagement&gt;

    &lt;properties&gt;
        &lt;java.version&gt;11&lt;/java.version&gt;
    &lt;/properties&gt;

    &lt;dependencies&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-webflux&lt;/artifactId&gt;
        &lt;/dependency&gt;

        &lt;dependency&gt;
            &lt;groupId&gt;software.amazon.awssdk&lt;/groupId&gt;
            &lt;artifactId&gt;sqs&lt;/artifactId&gt;
        &lt;/dependency&gt;

        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-test&lt;/artifactId&gt;
            &lt;scope&gt;test&lt;/scope&gt;
            &lt;exclusions&gt;
                &lt;exclusion&gt;
                    &lt;groupId&gt;org.junit.vintage&lt;/groupId&gt;
                    &lt;artifactId&gt;junit-vintage-engine&lt;/artifactId&gt;
                &lt;/exclusion&gt;
            &lt;/exclusions&gt;
        &lt;/dependency&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;io.projectreactor&lt;/groupId&gt;
            &lt;artifactId&gt;reactor-test&lt;/artifactId&gt;
            &lt;scope&gt;test&lt;/scope&gt;
        &lt;/dependency&gt;
    &lt;/dependencies&gt;

    &lt;build&gt;
        &lt;plugins&gt;
            &lt;plugin&gt;
                &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
                &lt;artifactId&gt;spring-boot-maven-plugin&lt;/artifactId&gt;
            &lt;/plugin&gt;
        &lt;/plugins&gt;
    &lt;/build&gt;

&lt;/project&gt;

```

With that, we need to configure our **SqsClient** to communicate with local. We can do that with something like:

```java
@Configuration
public class AwsSqsConfig {

    @Bean
    public SqsAsyncClient amazonSQSAsyncClient() {
        return SqsAsyncClient.builder()
                .endpointOverride(URI.create(&#34;http://localhost:4566&#34;))
                .region(Region.US_EAST_1)
                .credentialsProvider(StaticCredentialsProvider.create(new AwsCredentials() {
                    @Override
                    public String accessKeyId() {
                        return &#34;FAKE&#34;;
                    }

                    @Override
                    public String secretAccessKey() {
                        return &#34;FAKE&#34;;
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
        LOG.info(&#34;hello!!!&#34;);
        CompletableFuture wat = sqsAsyncClient.getQueueUrl(GetQueueUrlRequest.builder().queueName(&#34;my-queue&#34;).build());
        GetQueueUrlResponse getQueueUrlResponse = wat.get();

        Mono.fromFuture(() -&gt; sqsAsyncClient.sendMessage(
                SendMessageRequest.builder()
                        .queueUrl(getQueueUrlResponse.queueUrl())
                        .messageBody(&#34;new message at second &#34; &#43; ZonedDateTime.now().getSecond())
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
export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;
export AWS_DEFAULT_REGION=us-east-1

Q_URL=$(aws --endpoint-url http://localhost:4566 sqs get-queue-url --queue-name &#34;my-queue&#34; --output text)
aws --endpoint-url http://localhost:4566 sqs receive-message --queue-url &#34;$Q_URL&#34;

```

You should see something like:

```json
{
    &#34;Messages&#34;: [
        {
            &#34;MessageId&#34;: &#34;5fef529f-8787-d931-b2f6-34127ae978cd&#34;,
            &#34;ReceiptHandle&#34;: &#34;duytrocbgdfbfnyiqpsvnsqroimuegaigttaueclycefoxfwtlwvnykealgmvybwnckqjjgyoedzsmxulazjcyqdhaalwztyddxkssqhqycqctxhfhavmyylvpybljldflzavfghwwjdlgyvfbiprwrirappaocctdcqzilufjoobllvekbinirmt&#34;,
            &#34;MD5OfBody&#34;: &#34;08550418f58bc838c192dc825693e5a6&#34;,
            &#34;Body&#34;: &#34;new message at second 30&#34;,
            &#34;Attributes&#34;: {
                &#34;SenderId&#34;: &#34;AIDAIT2UOQQY3AUEKVGXU&#34;,
                &#34;SentTimestamp&#34;: &#34;1600551210970&#34;,
                &#34;ApproximateReceiveCount&#34;: &#34;1&#34;,
                &#34;ApproximateFirstReceiveTimestamp&#34;: &#34;1600551215120&#34;
            }
        }
    ]
}

```

And you should be good to go
