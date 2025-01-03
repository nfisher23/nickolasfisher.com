---
title: "DynamoDB Streams and Python: A Working Introduction"
date: 2020-07-26T21:54:59
draft: false
tags: [distributed systems, DevOps, aws, dynamodb]
---

DynamoDB Streams is AWS&#39;s home grown [Change Data Capture \[CDC\]](https://en.wikipedia.org/wiki/Change_data_capture) mechanism, which allows the consumer of the stream to see records probably in approximately the order they were created \[it&#39;s basically impossible, at scale, to guarantee that all records across all partitions will somehow stream the data in exactly the same order that it was written\]. This is a pretty fantastic feature because it allows us to reliably do _---something---_ after we add new data, update existing data, or delete existing data. As long as all the stream records are read and processed, we can ensure at least once processing on data changes and then go sleep soundly at night knowing that there is one less edge case in our application. Combine that with the natural scale that DynamoDB provides via its leaderless architecture and you can build this thing once and probably never have to worry about it handling more load ever again.

This post is basically a hands on introduction to streams, using a bit of bash and python to read through stream records in our local environment. No AWS infrastructure or fear of a high bill required.

## Local DynamoDB And Data Setup

Start by setting up a local dynamo container. I&#39;m going to use docker compose \[ **docker-compose.yml**\]:

```yaml
version: &#39;3.7&#39;
services:
  dynamodb-local:
    image: amazon/dynamodb-local
    container_name: dynamodb-local
    ports:
      - &#34;8000:8000&#34;

```

You can start up the container now with:

```bash
docker-compose up -d

```

Now I&#39;m going to use the AWS CLI to set up some data, creating our familiar Phones table \[with streams enabled! Writing only the key to the stream in this case\] and inserting some also familiar data:

```bash
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name Phones \
  --attribute-definitions AttributeName=Company,AttributeType=S AttributeName=Model,AttributeType=S \
  --key-schema AttributeName=Company,KeyType=HASH AttributeName=Model,KeyType=RANGE \
  --stream-specification StreamEnabled=true,StreamViewType=KEYS_ONLY

TEMPLATE=$(cat &lt;&lt;&#39;EOF&#39;
{
    &#34;Company&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    },
    &#34;Model&#34;: {
        &#34;S&#34;: &#34;%s&#34;
    },
    &#34;Colors&#34;: {
        &#34;SS&#34;: [
            &#34;Green&#34;,
            &#34;Blue&#34;,
            &#34;Orange&#34;
        ]
    },
    &#34;Size&#34;: {
        &#34;N&#34;: &#34;%s&#34;
    }
}
EOF
)

put_dynamo_local() {
    ITEM=&#34;$1&#34;
    # echo $ITEM = json_pp
    # return 0
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb put-item \
      --table-name Phones \
      --item &#34;$ITEM&#34;
}

MOTO_COOL=$(printf &#34;$TEMPLATE&#34; &#34;Motorola&#34; &#34;Cool Phone&#34; &#34;12&#34;)
MOTO_LAME=$(printf &#34;$TEMPLATE&#34; &#34;Motorola&#34; &#34;Lame Phone&#34; &#34;9&#34;)
GOOGL_NICE=$(printf &#34;$TEMPLATE&#34; &#34;Goole&#34; &#34;Awesome Phone&#34; &#34;8&#34;)
GOOGL_MEAN=$(printf &#34;$TEMPLATE&#34; &#34;Google&#34; &#34;Confusing Phone&#34; &#34;18&#34;)

put_dynamo_local &#34;$MOTO_COOL&#34;
put_dynamo_local &#34;$MOTO_LAME&#34;
put_dynamo_local &#34;$GOOGL_NICE&#34;
put_dynamo_local &#34;$GOOGL_MEAN&#34;

```

At this point, we have four items in our table and the data setup is complete. You can refer to [a previous post on introducing DynamoDB](https://nickolasfisher.com/blog/DynamoDB-Basics-A-Hands-On-Tutorial) that goes into a bit more detail on how that code works if that helps you along.

## A Python Script to Process It

Now that we have data, let&#39;s figure out how to process it.

I elected to use python3 and the [AWS SDK for python](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html) to actually process the stream records. There are a few key things to mention:

- There are two different types of boto3 &#34;client&#34; that we care about here: [DynamoDB](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb.html) and [DynamoDBStreams](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodbstreams.html). In this case I used the dynamoDB client to get enough information to start using the appropriate stream via its ARN.
- The concept of a Stream shard is important: Each &#34;shard&#34; is like a group of stream records and let&#39;s you iterate through them in whatever order you want \[e.g. start at the latest record, start at the earliest record, start at the first record after xxx, whatever\]. You can only read stream records from a shard.


I also just use a wrapper class around boto3 to make my life a little easier, here&#39;s the code:

```python
import boto3
import json

def get_local_client(resource_name):
    return boto3.client(resource_name,
                        aws_access_key_id=&#34;FAKE&#34;,
                        aws_secret_access_key=&#34;FAKE&#34;,
                        endpoint_url=&#39;http://localhost:8000&#39;,
                        region_name=&#39;us-west-2&#39;)

class BotoWrapper(object):

    def __init__(self):
        self.local_dynamodb_client = get_local_client(&#39;dynamodb&#39;)
        self.local_dynamodb_streams_client = get_local_client(&#39;dynamodbstreams&#39;)

    def get_stream_arn(self):
        describe_table_response = self.local_dynamodb_client.describe_table(TableName=&#39;Phones&#39;)
        return describe_table_response[&#39;Table&#39;][&#39;LatestStreamArn&#39;]

    def get_shard_object_array(self, stream_arn):
        describe_stream_response = self.local_dynamodb_streams_client.describe_stream(StreamArn=stream_arn)
        return describe_stream_response[&#39;StreamDescription&#39;][&#39;Shards&#39;]

    def get_data_from_shard(self, shard_iterator):
        records_in_response = self.local_dynamodb_streams_client.get_records(ShardIterator=shard_iterator, Limit=1000)
        return records_in_response[&#39;Records&#39;]

    def run_example(self):
        stream_arn = self.get_stream_arn()
        shards = self.get_shard_object_array(stream_arn)

        for shard in shards:
            iterator = self.local_dynamodb_streams_client.get_shard_iterator(
                StreamArn=stream_arn,
                ShardId=shard[&#39;ShardId&#39;],
                ShardIteratorType=&#39;TRIM_HORIZON&#39;
            )
            records = self.get_data_from_shard(iterator[&#39;ShardIterator&#39;])
            for record in records:
                print(&#34;####  DYNAMO RECORD  ####&#34;)
                print(&#34;&#34;)
                print(json.dumps(record,
                                 sort_keys=True,
                                 indent=4,
                                 default=str))
                print(&#34;&#34;)
                print(&#34;&#34;)

if __name__ == &#39;__main__&#39;:
    boto_wrapper = BotoWrapper()
    boto_wrapper.run_example()

```

To actually run this, make sure you have boto3 installed with:

```bash
pip3 install boto3

```

Then you should be able to run this with:

```bash
python3 read-stream.py

```

When I run this, I see four stream records as expected, and one of them looks like this:

```json

{
    &#34;awsRegion&#34;: &#34;ddblocal&#34;,
    &#34;dynamodb&#34;: {
        &#34;ApproximateCreationDateTime&#34;: &#34;2020-08-02 14:24:00-07:00&#34;,
        &#34;Keys&#34;: {
            &#34;Company&#34;: {
                &#34;S&#34;: &#34;Motorola&#34;
            },
            &#34;Model&#34;: {
                &#34;S&#34;: &#34;Cool Phone&#34;
            }
        },
        &#34;SequenceNumber&#34;: &#34;000000000000000000001&#34;,
        &#34;SizeBytes&#34;: 30,
        &#34;StreamViewType&#34;: &#34;KEYS_ONLY&#34;
    },
    &#34;eventID&#34;: &#34;74fbc7ae-ae3f-417b-a3fa-4325d6a676b0&#34;,
    &#34;eventName&#34;: &#34;INSERT&#34;,
    &#34;eventSource&#34;: &#34;aws:dynamodb&#34;,
    &#34;eventVersion&#34;: &#34;1.1&#34;
}

```

Feel free to have a look at other [DynamoDBStreams API operations](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodbstreams.html) available to you as a python developer.

Finally, if you&#39;re actually going to be running this at scale, I would recommend you use an AWS Lambda triggering on a stream record or the Kinesis adapter--almost for sure you will save both time and money doing so. This was primarily meant as an exercise to understand how streams work and to enable easy local development.
