---
title: "Why Redis Pub/Sub is not SQS, and Vice Versa"
date: 2021-04-01T00:00:00
draft: false
---

[Redis has a pub/sub feature](https://redis.io/topics/pubsub) whereby there are publishers and subscribers, and publishers can fanout messages to subscribers. SQS \[ [amazon&#39;s simple queue service](https://aws.amazon.com/sqs/)\] has message senders and receivers. They can both be useful, but in practice they produce different results.

### How Redis Pub/Sub Works: An Example

Every subscriber to a channel in redis will receive the message sent by the publisher. I can demonstrate this with a simple example. Let&#39;s say you start up a local redis instance with docker, something like:

``` bash
docker run --rm -d -p 127.0.0.1:6379:6379/tcp redis
814a1bcb5abcb17dcb1b657fd3e8563ada0a2b1d9df5e4f1b09c229139f8964a

```

Now you connect to redis from two different terminals and subscribe to the same channel:

``` bash
