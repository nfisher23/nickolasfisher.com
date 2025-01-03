---
title: "Why Redis Pub/Sub is not SQS, and Vice Versa"
date: 2021-04-24T23:52:19
draft: false
---

[Redis has a pub/sub feature](https://redis.io/topics/pubsub) whereby there are publishers and subscribers, and publishers can fanout messages to subscribers. SQS \[ [amazon&#39;s simple queue service](https://aws.amazon.com/sqs/)\] has message senders and receivers. They can both be useful, but in practice they produce different results.

### How Redis Pub/Sub Works: An Example

Every subscriber to a channel in redis will receive the message sent by the publisher. I can demonstrate this with a simple example. Let&#39;s say you start up a local redis instance with docker, something like:

```bash
docker run --rm -d -p 127.0.0.1:6379:6379/tcp redis
814a1bcb5abcb17dcb1b657fd3e8563ada0a2b1d9df5e4f1b09c229139f8964a

```

Now you connect to redis from two different terminals and subscribe to the same channel:

```bash
# first terminal
$ redis-cli
127.0.0.1:6379&gt; SUBSCRIBE a-channel
Reading messages... (press Ctrl-C to quit)
1) &#34;subscribe&#34;
2) &#34;a-channel&#34;
3) (integer) 1

# second terminal
$ redis-cli
127.0.0.1:6379&gt; SUBSCRIBE a-channel
Reading messages... (press Ctrl-C to quit)
1) &#34;subscribe&#34;
2) &#34;a-channel&#34;
3) (integer) 1

```

In a third terminal, you publish to **a-channel**, which is what we are subscribing to in the previously opened two terminals:

```bash
$ redis-cli
127.0.0.1:6379&gt; PUBLISH a-channel &#34;everyone sees this&#34;
(integer) 2

```

The returned number is 2, which means two subscribers received this response. Here is the terminal output from both of them:

```bash
# first terminal
1) &#34;message&#34;
2) &#34;a-channel&#34;
3) &#34;everyone sees this&#34;

# second terminal
1) &#34;message&#34;
2) &#34;a-channel&#34;
3) &#34;everyone sees this&#34;

```

This means that, if you&#39;re running multiple instances of the same application, then every instance of the application will get your message.

### How SQS Works: An Example

Let&#39;s say you start up a local SQS mock using localstack, with a docker-compose.yaml like so:

```bash
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

You then bring up your localstack container with:

```bash
docker-compose up -d

```

Now let&#39;s repeat what is effectively the same experiment. First, if you&#39;re following along, you need to make sure you have credentials or your aws cli tool will complain:

```bash
export AWS_SECRET_ACCESS_KEY=&#34;FAKE&#34;
export AWS_ACCESS_KEY_ID=&#34;FAKE&#34;
export AWS_DEFAULT_REGION=us-east-1

```

Note that you&#39;ll also unfortunately need to specify those environment variables for each of the three terminals we are about to open. In the first and second terminal, run this command to pull a message off of the SQS queue as soon as one becomes available:

```bash
# first and second terminal
aws --endpoint-url http://localhost:4566 sqs receive-message --queue-url http://localhost:4566/000000000000/test-queue --wait-time-seconds 20

```

While those two commands are waiting for a response \[note: you have 20 seconds until they just give up, so you might need to rerun those before this final one to really get the point of this article\], in your third terminal run this:

```bash
aws --endpoint-url http://localhost:4566 sqs send-message --message-body &#34;hello&#34; --queue-url http://localhost:4566/0000000000/test-queue

```

What should happen under low throughput, from &#34;real&#34; SQS, is that one of the clients trying to get a message actually get it. The other client is still waiting. SQS guarantees at-least-once delivery, but under normal circumstances and most of the time you will get about-once delivery. On my computer, I saw this:

```bash
# first terminal
$ aws --endpoint-url http://localhost:4566 sqs receive-message --queue-url http://localhost:4566/000000000000/test-queue --wait-time-seconds 20
{
    &#34;Messages&#34;: [
        {
            &#34;MessageId&#34;: &#34;ca46e741-6522-b27b-e454-76f514a9a851&#34;,
            &#34;ReceiptHandle&#34;: &#34;mkdoaefeokewmrbqxmhnovuokoslnvwhkcxnkzafvxuwzbrkritnqweummmquejiajlcjkpnzhezwolaodklfrutbjeutggqfoefaypapvzihvhbuvfohxjzjxdtkmhclnxqdmiqwkrykghrmywomdlitbnsxjgkhojdoeynpxjpgoujeyxkhovsi&#34;,
            &#34;MD5OfBody&#34;: &#34;5d41402abc4b2a76b9719d911017c592&#34;,
            &#34;Body&#34;: &#34;hello&#34;,
            &#34;Attributes&#34;: {
                &#34;SenderId&#34;: &#34;AIDAIT2UOQQY3AUEKVGXU&#34;,
                &#34;SentTimestamp&#34;: &#34;1619914864555&#34;,
                &#34;ApproximateReceiveCount&#34;: &#34;1&#34;,
                &#34;ApproximateFirstReceiveTimestamp&#34;: &#34;1619914864566&#34;
            }
        }
    ]
}

# second terminal
$ aws --endpoint-url http://localhost:4566 sqs receive-message --queue-url http://localhost:4566/000000000000/test-queue --wait-time-seconds 20

$ # timed out waiting for a response

```

### What this means in practice

So, which one should I use? Well, it depends on whether you want _all instances of your application to get the message_ or not. If your just sending a message as a job \[to do a piece of work, like update the database\], then you want SQS \[both because of its about-once-delivery characteristics, but also because of its durability guarantees, which redis does not offer because it&#39;s in memory\]. If you need to send a message to every instance in your application, for example to invalidate an in memory cache, then you probably want to use redis pub/sub.
