---
title: "How to Setup SNS Message Forwarding to SQS with the AWS CLI"
date: 2020-08-01T00:00:00
draft: false
---

[Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/welcome.html) is AWS&#39;s solution to pub/sub. In a large, distributed system, decoupling _events_ from services that _need to act on those events_ allows for teams that own different services to better work in parallel, and also prevents the need for coordinating code deploys to deliver new features. If a services is already publishing a generic event, other services can hook into that event and act on them without needing anything but a bit of infrastructure.

Most commonly, you will want to use SNS with Amazon SQS. Multiple queues can subscribe to the same SNS topic, and with no filters setup, every event sent to the SNS topic will be forwarded to all the SQS queues for you automatically. I&#39;m going to show you how to do that with the CLI using localstack in this post.

### Start localstack on your machine, configure CLI

I took the **docker-compose.yaml** from [the root of the localstack github repository](https://github.com/localstack/localstack/blob/master/docker-compose.yml):

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

Go ahead and copy paste that thing and run \[in the same directory\]:

``` bash
docker-compose up -d

```

We can set some dummy environment variables to make localstack and the CLI happy:

``` bash
export AWS_DEFAULT_REGION=us-west-2export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;
export AWS_DEFAULT_REGION=us-east-1

```

You can test that your CLI is working with something like

``` bash
aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name &#34;test&#34;

```

If all is well you&#39;ll see an output like:

``` json
{
    &#34;QueueUrls&#34;: [
        &#34;http://localhost:4566/000000000000/test&#34;
    ]
}

```

### Actually Do the Forwarding Now

We will first need to create both the SNS topic and the SQS queue (these are both idempotent operations):

``` bash
QUEUE_NAME=&#34;my-queue&#34;
TOPIC_NAME=&#34;my-topic&#34;
aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name &#34;$QUEUE_NAME&#34; --output text
aws --endpoint-url http://localhost:4566 sns create-topic --output text --name &#34;$TOPIC_NAME&#34;

```

Creating the queue will by default return the queue url, and creating the SNS topic will by default return its ARN (Amazon Resource Name). It will make our lives easier if we store those as bash variables:

``` bash
QUEUE_URL=$(aws --endpoint-url http://localhost:4566 sqs create-queue --queue-name &#34;$QUEUE_NAME&#34; --output text)
TOPIC_ARN=$(aws --endpoint-url http://localhost:4566 sns create-topic --output text --name &#34;$TOPIC_NAME&#34;)

```

To set up a subscription, we also are going to need to grab the SQS queue ARN. I will do that by leveraging [jq](https://stedolan.github.io/jq/manual/):

``` bash
QUEUE_ARN=$(aws --endpoint-url http://localhost:4566 sqs get-queue-attributes --queue-url &#34;$QUEUE_URL&#34; | jq -r &#34;.Attributes.QueueArn&#34;)

```

Finally, we will set up the link between the two \[and also grab the ARN of the subscription\] with:

``` bash
SUBSCRIPTION_ARN=$(aws --endpoint-url http://localhost:4566 sns subscribe --topic-arn &#34;$TOPIC_ARN&#34; --protocol sqs --notification-endpoint &#34;$QUEUE_ARN&#34; --output text)

```

At this point we should be able to see our subscription in a list with:

``` bash
aws --endpoint-url http://localhost:4566 sns list-subscriptions

```

The output from that should look something like:

``` json
{
    &#34;Subscriptions&#34;: [
        {
            &#34;SubscriptionArn&#34;: &#34;arn:aws:sns:us-east-1:000000000000:my-topic:0243d3b4-4cdd-41c8-abbf-d8f0f83a74c5&#34;,
            &#34;Owner&#34;: &#34;&#34;,
            &#34;Protocol&#34;: &#34;sqs&#34;,
            &#34;Endpoint&#34;: &#34;arn:aws:sqs:us-east-1:000000000000:my-queue&#34;,
            &#34;TopicArn&#34;: &#34;arn:aws:sns:us-east-1:000000000000:my-topic&#34;
        }
    ]
}

```

And if we send a message to the SNS topic, we should be able to see a response by polling the SQS queue:

``` bash
aws sns --endpoint-url http://localhost:4566 publish --topic-arn &#34;$TOPIC_ARN&#34; --message &#34;hello!&#34;
aws sqs --endpoint-url http://localhost:4566 receive-message --queue-url &#34;$QUEUE_URL&#34;

```

If you take a close look at the message as SQS receives it, you will see that the message was not delivered in its original form:

``` json
{
    &#34;Messages&#34;: [
        {
            &#34;MessageId&#34;: &#34;24810d56-1f40-0569-d5f9-751dbc881fcc&#34;,
            &#34;ReceiptHandle&#34;: &#34;chbhoztdlwckzmbjctnecnyafkfkdwzgonqetkwoxvvdxfohrmgplcsdgmskwiwhienohhefdrhmqxxjrqtuamoliwpfwzldugbloxrxjjnmpatswuoetnpoudjugphvgzywrzjexdvktenqiaxczofiphjstzslnygpdxwjsarlgiuhpeioohvav&#34;,
            &#34;MD5OfBody&#34;: &#34;e999e85bed5f7a06f9b5548304e9ea49&#34;,
            &#34;Body&#34;: &#34;{\&#34;Type\&#34;: \&#34;Notification\&#34;, \&#34;MessageId\&#34;: \&#34;6af3f1a1-07d5-4f16-b1d3-a3dc3656e107\&#34;, \&#34;Token\&#34;: null, \&#34;TopicArn\&#34;: \&#34;arn:aws:sns:us-east-1:000000000000:my-topic\&#34;, \&#34;Message\&#34;: \&#34;hello!\&#34;, \&#34;SubscribeURL\&#34;: null, \&#34;Timestamp\&#34;: \&#34;2020-08-22T22:27:45.235Z\&#34;, \&#34;SignatureVersion\&#34;: \&#34;1\&#34;, \&#34;Signature\&#34;: \&#34;EXAMPLEpH&#43;..\&#34;, \&#34;SigningCertURL\&#34;: \&#34;https://sns.us-east-1.amazonaws.com/SimpleNotificationService-0000000000000000000000.pem\&#34;}&#34;,
            &#34;Attributes&#34;: {
                &#34;SenderId&#34;: &#34;AIDAIT2UOQQY3AUEKVGXU&#34;,
                &#34;SentTimestamp&#34;: &#34;1598135265266&#34;,
                &#34;ApproximateReceiveCount&#34;: &#34;1&#34;,
                &#34;ApproximateFirstReceiveTimestamp&#34;: &#34;1598135265910&#34;
            }
        }
    ]
}

```

This is because **raw message delivery** is not **true** when you first create the subscription. You can change that with one more CLI command:

``` bash
aws --endpoint-url http://localhost:4566 sns set-subscription-attributes \
  --subscription-arn &#34;$SUBSCRIPTION_ARN&#34; --attribute-name RawMessageDelivery --attribute-value true

```

Now when you ask for a message from SQS you will see it in its proper form:

``` json
{
    &#34;Messages&#34;: [
        {
            &#34;MessageId&#34;: &#34;e03aa463-61d2-3910-97ca-d0eb13274082&#34;,
            &#34;ReceiptHandle&#34;: &#34;tcjqhbygluhgeyjgqcahrxseqztnwlkppciqjoollvlavhruexvryomumruvrpkiykljcouekexunqijuswzccjzzclbbwreafvmusqnbtqdpclnzgwatxnxgwvegzsrwkzinpavmdekeqqwdvyktpibywifsbeognewqtibjjwnvdjrdwnbhujtn&#34;,
            &#34;MD5OfBody&#34;: &#34;5a8dd3ad0756a93ded72b823b19dd877&#34;,
            &#34;Body&#34;: &#34;hello!&#34;,
            &#34;Attributes&#34;: {
                &#34;SenderId&#34;: &#34;AIDAIT2UOQQY3AUEKVGXU&#34;,
                &#34;SentTimestamp&#34;: &#34;1598135539742&#34;,
                &#34;ApproximateReceiveCount&#34;: &#34;1&#34;,
                &#34;ApproximateFirstReceiveTimestamp&#34;: &#34;1598135546283&#34;
            }
        }
    ]
}

```

And you should be good to go.


