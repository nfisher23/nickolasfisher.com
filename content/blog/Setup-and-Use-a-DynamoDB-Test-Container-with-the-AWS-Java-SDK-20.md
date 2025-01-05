---
title: "Setup and Use a DynamoDB Test Container with the AWS Java SDK 2.0"
date: 2021-04-10T16:13:09
draft: false
tags: [java, aws, dynamodb]
---

The source code for this article [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo).

Using [embedded dynamodb for testing](https://nickolasfisher.com/blog/configuring-an-in-memory-dynamodb-instance-with-java-for-integration-testing) is, in my experience, kind of flakey and unpredictable. Because of the weird way it pulls in SQLite on a per operating system basis, it can sometimes work locally and not work on the build server. Sometimes it's just not working for some unexplained reason and wiping the directory that the code is in and re-cloning fixes it. Not a fun time.

Enter [test containers](https://www.testcontainers.org/). The drawback of test containers is that you need a docker daemon running wherever you're building your app, but outside of that they work very well. And because docker was built specifically to handle the portability issues involved with supporting different OS flavors and versions, anytime you need a mock service or a real service it will work much more predictably. This article will walk you through how to setup a dynamodb test container and use it in java.

### The Example

To start with, you'll need to add a couple of dependencies to your **pom.xml** \[or your build.gradle, but I'm using maven for this example\]:

```xml
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>testcontainers</artifactId>
            <version>1.15.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>1.15.2</version>
            <scope>test</scope>
        </dependency>

```

Assuming you're using junit 5, you're a couple of annotations away from having what you want:

```java
@Testcontainers
public class DynamoTestContainerTest {

    private static DynamoDbAsyncClient dynamoDbAsyncClient;

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
            DockerImageName.parse("amazon/dynamodb-local")
    ).withExposedPorts(8000);

    @BeforeEach
    public void setupDynamoClient() {
        dynamoDbAsyncClient = getDynamoClient();
    }

    private static DynamoDbAsyncClient getDynamoClient() {
        return DynamoDbAsyncClient.builder()
                .region(Region.US_EAST_1)
                .endpointOverride(URI.create("http://localhost:" + genericContainer.getFirstMappedPort()))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create("FAKE", "FAKE")))
                .build();
    }
}

```

If you're not using junit 5, you will basically need to start the container yourself with a **@BeforeEach** annotation. That is relatively straightforward and there's a similar example \[using a different container image, but everything else is the same\] in a previous article on [a redis test container for lettuce](https://nickolasfisher.com/blog/how-to-use-a-redis-test-container-with-lettucespring-boot-webflux).

With this in place, we have our container running and we can create a client ready to use it. I'll do a bad thing and copy-paste some code from the other test class to prove it will actually work once we use it. Here's the full example:

```java
public class DynamoTestContainerTest {

    public static final String COMPANY = "Company";
    public static final String MODEL = "Model";

    private static DynamoDbAsyncClient dynamoDbAsyncClient;

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
            DockerImageName.parse("amazon/dynamodb-local")
    ).withExposedPorts(8000);

    @BeforeEach
    public void setupDynamoClient() {
        dynamoDbAsyncClient = getDynamoClient();
    }

    @Test
    public void testStuff() throws Exception {
        ListTablesResponse listTablesResponse = dynamoDbAsyncClient.listTables().get();

        int totalTablesBeforeCreation = listTablesResponse.tableNames().size();

        createTableAsync("Phones").get();

        ListTablesResponse listTablesResponseAfterCreation = dynamoDbAsyncClient.listTables().get();

        assertThat(listTablesResponseAfterCreation.tableNames().size()).isEqualTo(totalTablesBeforeCreation + 1);
    }

    private static DynamoDbAsyncClient getDynamoClient() {
        return DynamoDbAsyncClient.builder()
                .region(Region.US_EAST_1)
                .endpointOverride(URI.create("http://localhost:" + genericContainer.getFirstMappedPort()))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create("FAKE", "FAKE")))
                .build();
    }

    private CompletableFuture<CreateTableResponse> createTableAsync(String tableName) {
        return dynamoDbAsyncClient.createTable(CreateTableRequest.builder()
                .keySchema(
                        KeySchemaElement.builder()
                                .keyType(KeyType.HASH)
                                .attributeName(COMPANY)
                                .build(),
                        KeySchemaElement.builder()
                                .keyType(KeyType.RANGE)
                                .attributeName(MODEL)
                                .build()
                )
                .attributeDefinitions(
                        AttributeDefinition.builder()
                                .attributeName(COMPANY)
                                .attributeType(ScalarAttributeType.S)
                                .build(),
                        AttributeDefinition.builder()
                                .attributeName(MODEL)
                                .attributeType(ScalarAttributeType.S)
                                .build()
                )
                .provisionedThroughput(ProvisionedThroughput.builder().readCapacityUnits(100L).writeCapacityUnits(100L).build())
                .tableName(tableName)
                .build()
        );
    }
}

```

And with that, you should be good to go.
