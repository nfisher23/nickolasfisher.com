---
title: "DynamoDB Streams and Python: A Working Introduction"
date: 2020-07-26T21:54:59
draft: false
tags: [distributed systems, DevOps, aws, dynamodb]
---

DynamoDB Streams is AWS's home grown [Change Data Capture \[CDC\]](https://en.wikipedia.org/wiki/Change_data_capture) mechanism, which allows the consumer of the stream to see records probably in approximately the order they were created \[it's basically impossible, at scale, to guarantee that all records across all partitions will somehow stream the data in exactly the same order that it was written\]. This is a pretty fantastic feature because it allows us to reliably do _---something---_ after we add new data, update existing data, or delete existing data. As long as all the stream records are read and processed, we can ensure at least once processing on data changes and then go sleep soundly at night knowing that there is one less edge case in our application. Combine that with the natural scale that DynamoDB provides via its leaderless architecture and you can build this thing once and probably never have to worry about it handling more load ever again.

This post is basically a hands on introduction to streams, using a bit of bash and python to read through stream records in our local environment. No AWS infrastructure or fear of a high bill required.

## Local DynamoDB And Data Setup

Start by setting up a local dynamo container. I'm going to use docker compose \[ **docker-compose.yml**\]:

```yaml
version: '3.7'
services:
  dynamodb-local:
    image: amazon/dynamodb-local
    container_name: dynamodb-local
    ports:
      - "8000:8000"

```

You can start up the container now with:

```bash
docker-compose up -d

```

Now I'm going to use the AWS CLI to set up some data, creating our familiar Phones table \[with streams enabled! Writing only the key to the stream in this case\] and inserting some also familiar data:

```bash
aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb create-table \
  --billing-mode PAY_PER_REQUEST \
  --table-name Phones \
  --attribute-definitions AttributeName=Company,AttributeType=S AttributeName=Model,AttributeType=S \
  --key-schema AttributeName=Company,KeyType=HASH AttributeName=Model,KeyType=RANGE \
  --stream-specification StreamEnabled=true,StreamViewType=KEYS_ONLY

TEMPLATE=$(cat <<'EOF'
{
    "Company": {
        "S": "%s"
    },
    "Model": {
        "S": "%s"
    },
    "Colors": {
        "SS": [
            "Green",
            "Blue",
            "Orange"
        ]
    },
    "Size": {
        "N": "%s"
    }
}
EOF
)

put_dynamo_local() {
    ITEM="$1"
    # echo $ITEM = json_pp
    # return 0
    aws --endpoint-url http://localhost:8000 --region=us-west-2 dynamodb put-item \
      --table-name Phones \
      --item "$ITEM"
}

MOTO_COOL=$(printf "$TEMPLATE" "Motorola" "Cool Phone" "12")
MOTO_LAME=$(printf "$TEMPLATE" "Motorola" "Lame Phone" "9")
GOOGL_NICE=$(printf "$TEMPLATE" "Goole" "Awesome Phone" "8")
GOOGL_MEAN=$(printf "$TEMPLATE" "Google" "Confusing Phone" "18")

put_dynamo_local "$MOTO_COOL"
put_dynamo_local "$MOTO_LAME"
put_dynamo_local "$GOOGL_NICE"
put_dynamo_local "$GOOGL_MEAN"

```

At this point, we have four items in our table and the data setup is complete. You can refer to [a previous post on introducing DynamoDB](https://nickolasfisher.com/blog/dynamodb-basics-a-hands-on-tutorial) that goes into a bit more detail on how that code works if that helps you along.

## A Python Script to Process It

Now that we have data, let's figure out how to process it.

I elected to use python3 and the [AWS SDK for python](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html) to actually process the stream records. There are a few key things to mention:

- There are two different types of boto3 "client" that we care about here: [DynamoDB](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb.html) and [DynamoDBStreams](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodbstreams.html). In this case I used the dynamoDB client to get enough information to start using the appropriate stream via its ARN.
- The concept of a Stream shard is important: Each "shard" is like a group of stream records and let's you iterate through them in whatever order you want \[e.g. start at the latest record, start at the earliest record, start at the first record after xxx, whatever\]. You can only read stream records from a shard.


I also just use a wrapper class around boto3 to make my life a little easier, here's the code:

```python
import boto3
import json

def get_local_client(resource_name):
    return boto3.client(resource_name,
                        aws_access_key_id="FAKE",
                        aws_secret_access_key="FAKE",
                        endpoint_url='http://localhost:8000',
                        region_name='us-west-2')

class BotoWrapper(object):

    def __init__(self):
        self.local_dynamodb_client = get_local_client('dynamodb')
        self.local_dynamodb_streams_client = get_local_client('dynamodbstreams')

    def get_stream_arn(self):
        describe_table_response = self.local_dynamodb_client.describe_table(TableName='Phones')
        return describe_table_response['Table']['LatestStreamArn']

    def get_shard_object_array(self, stream_arn):
        describe_stream_response = self.local_dynamodb_streams_client.describe_stream(StreamArn=stream_arn)
        return describe_stream_response['StreamDescription']['Shards']

    def get_data_from_shard(self, shard_iterator):
        records_in_response = self.local_dynamodb_streams_client.get_records(ShardIterator=shard_iterator, Limit=1000)
        return records_in_response['Records']

    def run_example(self):
        stream_arn = self.get_stream_arn()
        shards = self.get_shard_object_array(stream_arn)

        for shard in shards:
            iterator = self.local_dynamodb_streams_client.get_shard_iterator(
                StreamArn=stream_arn,
                ShardId=shard['ShardId'],
                ShardIteratorType='TRIM_HORIZON'
            )
            records = self.get_data_from_shard(iterator['ShardIterator'])
            for record in records:
                print("####  DYNAMO RECORD  ####")
                print("")
                print(json.dumps(record,
                                 sort_keys=True,
                                 indent=4,
                                 default=str))
                print("")
                print("")

if __name__ == '__main__':
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
    "awsRegion": "ddblocal",
    "dynamodb": {
        "ApproximateCreationDateTime": "2020-08-02 14:24:00-07:00",
        "Keys": {
            "Company": {
                "S": "Motorola"
            },
            "Model": {
                "S": "Cool Phone"
            }
        },
        "SequenceNumber": "000000000000000000001",
        "SizeBytes": 30,
        "StreamViewType": "KEYS_ONLY"
    },
    "eventID": "74fbc7ae-ae3f-417b-a3fa-4325d6a676b0",
    "eventName": "INSERT",
    "eventSource": "aws:dynamodb",
    "eventVersion": "1.1"
}

```

Feel free to have a look at other [DynamoDBStreams API operations](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodbstreams.html) available to you as a python developer.

Finally, if you're actually going to be running this at scale, I would recommend you use an AWS Lambda triggering on a stream record or the Kinesis adapter--almost for sure you will save both time and money doing so. This was primarily meant as an exercise to understand how streams work and to enable easy local development.
