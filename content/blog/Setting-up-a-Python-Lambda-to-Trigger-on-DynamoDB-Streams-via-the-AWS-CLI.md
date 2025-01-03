---
title: "Setting up a Python Lambda to Trigger on DynamoDB Streams via the AWS CLI"
date: 2021-02-01T00:00:00
draft: false
---

DynamoDB streams record information about what has changed in a DynamoDB table, and AWS lambdas are ways to run code without managing servers yourself. DynamoDB streams also have an integration with AWS Lambdas so that any change to a DynamoDB table can be processed by an AWS Lambda--still without worrying about keeping your servers up or maintaining them. That is the subject of this post.

We&#39;ll be using [localstack](https://github.com/localstack/localstack) to prove this out. You can follow along with previous blog posts \[like this one about [python lambdas and localstack](https://nickolasfisher.com/blog/Basic-Python-Lambda-Function-Uploads-using-the-AWS-CLI)\] of mine for how to do AWS stuff with localstack.

**Important Note:** Localstack has a bug, which they claim to have fixed, where lambdas invoked inside the localstack container can&#39;t call other localstack resources, like sns or s3. I was able to hack around this and will cover the hack towards the end of this article. If you need to call other AWS resources with your lambda \[as will very often be the case\], then to really test it you&#39;ll just have to bite the bullet and use AWS itself as of now.

## Create AWS Resources and Lamdba

Assuming you already understand how to get localstack up and running locally, we&#39;ll need to create a dynamo table to work with:

``` bash
