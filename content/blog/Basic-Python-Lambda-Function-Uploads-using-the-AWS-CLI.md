---
title: "Basic Python Lambda Function Uploads using the AWS CLI"
date: 2021-02-01T00:00:00
draft: false
---

AWS Lambda functions were the first &#34;serverless&#34; way to run code. Of course, there are still servers, but the point is that you can nearly forget about managing those servers and all of that is owned by AWS.

Lambda functions are called functions because that&#39;s literally what you upload to AWS: a function that takes an **event** and **context**. The event will just be a JSON representation of something that happens on the system \[the structure of the event depends on what is invoking the lambda function\], and the context contains a bunch of metadata about the invocation that you usually don&#39;t really care about.

A simple lambda function \[that we&#39;ll be using in this article\] could look like this:

``` python
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

Then simply navigate to where you&#39;ve placed the file in your filesystem and run:

``` bash
$ docker-compose up

```

## Deploy and run our Python Lambda Function

To actually start using our lambda function now that we have our infrastructure and code ready, we will first need to create an IAM role to run the lambda, then attach a policy to that role to allow it to operate as a lambda. We could optionally create our own policy, but AWS has a bunch of policies ready for us to already use, and for this article we&#39;ll just reuse it:

``` bash
