---
title: "Setup and Use a DynamoDB Test Container with the AWS Java SDK 2.0"
date: 2021-04-01T00:00:00
draft: false
---

The source code for this article [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo).

Using [embedded dynamodb for testing](https://nickolasfisher.com/blog/Configuring-an-In-Memory-DynamoDB-instance-with-Java-for-Integration-Testing) is, in my experience, kind of flakey and unpredictable. Because of the weird way it pulls in SQLite on a per operating system basis, it can sometimes work locally and not work on the build server. Sometimes it&#39;s just not working for some unexplained reason and wiping the directory that the code is in and re-cloning fixes it. Not a fun time.

Enter [test containers](https://www.testcontainers.org/). The drawback of test containers is that you need a docker daemon running wherever you&#39;re building your app, but outside of that they work very well. And because docker was built specifically to handle the portability issues involved with supporting different OS flavors and versions, anytime you need a mock service or a real service it will work much more predictably. This article will walk you through how to setup a dynamodb test container and use it in java.

### The Example

To start with, you&#39;ll need to add a couple of dependencies to your **pom.xml** \[or your build.gradle, but I&#39;m using maven for this example\]:

``` xml
        &lt;dependency&gt;
            &lt;groupId&gt;org.testcontainers&lt;/groupId&gt;
            &lt;artifactId&gt;testcontainers&lt;/artifactId&gt;
            &lt;version&gt;1.15.2&lt;/version&gt;
            &lt;scope&gt;test&lt;/scope&gt;
        &lt;/dependency&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;org.testcontainers&lt;/groupId&gt;
            &lt;artifactId&gt;junit-jupiter&lt;/artifactId&gt;
            &lt;version&gt;1.15.2&lt;/version&gt;
            &lt;scope&gt;test&lt;/scope&gt;
        &lt;/dependency&gt;

```

Assuming you&#39;re using junit 5, you&#39;re a couple of annotations away from having what you want:

``` java
@Testcontainers
public class DynamoTestContainerTest {

    private static DynamoDbAsyncClient dynamoDbAsyncClient;

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
            DockerImageName.parse(&#34;amazon/dynamodb-local&#34;)
    ).withExposedPorts(8000);

    @BeforeEach
    public void setupDynamoClient() {
        dynamoDbAsyncClient = getDynamoClient();
    }

    private static DynamoDbAsyncClient getDynamoClient() {
        return DynamoDbAsyncClient.builder()
                .region(Region.US_EAST_1)
                .endpointOverride(URI.create(&#34;http://localhost:&#34; &#43; genericContainer.getFirstMappedPort()))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(&#34;FAKE&#34;, &#34;FAKE&#34;)))
                .build();
    }
}

```

If you&#39;re not using junit 5, you will basically need to start the container yourself with a **@BeforeEach** annotation. That is relatively straightforward and there&#39;s a similar example \[using a different container image, but everything else is the same\] in a previous article on [a redis test container for lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux).

With this in place, we have our container running and we can create a client ready to use it. I&#39;ll do a bad thing and copy-paste some code from the other test class to prove it will actually work once we use it. Here&#39;s the full example:

``` java
public class DynamoTestContainerTest {

    public static final String COMPANY = &#34;Company&#34;;
    public static final String MODEL = &#34;Model&#34;;

    private static DynamoDbAsyncClient dynamoDbAsyncClient;

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
            DockerImageName.parse(&#34;amazon/dynamodb-local&#34;)
    ).withExposedPorts(8000);

    @BeforeEach
    public void setupDynamoClient() {
        dynamoDbAsyncClient = getDynamoClient();
    }

    @Test
    public void testStuff() throws Exception {
        ListTablesResponse listTablesResponse = dynamoDbAsyncClient.listTables().get();

        int totalTablesBeforeCreation = listTablesResponse.tableNames().size();

        createTableAsync(&#34;Phones&#34;).get();

        ListTablesResponse listTablesResponseAfterCreation = dynamoDbAsyncClient.listTables().get();

        assertThat(listTablesResponseAfterCreation.tableNames().size()).isEqualTo(totalTablesBeforeCreation &#43; 1);
    }

    private static DynamoDbAsyncClient getDynamoClient() {
        return DynamoDbAsyncClient.builder()
                .region(Region.US_EAST_1)
                .endpointOverride(URI.create(&#34;http://localhost:&#34; &#43; genericContainer.getFirstMappedPort()))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(&#34;FAKE&#34;, &#34;FAKE&#34;)))
                .build();
    }

    private CompletableFuture&lt;CreateTableResponse&gt; createTableAsync(String tableName) {
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


