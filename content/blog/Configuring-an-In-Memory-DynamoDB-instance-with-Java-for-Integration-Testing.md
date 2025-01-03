---
title: "Configuring an In Memory DynamoDB instance with Java for Integration Testing"
date: 2020-10-10T00:02:25
draft: false
tags: [java, reactive, aws, dynamodb, webflux]
---

While using the AWS SDK 2.0, which has support for reactive programming, it became clear that there was no straightforward support for an embedded dynamo db instance for testing. I spent a fair amount of time figuring it out by starting with [this github link](https://github.com/aws/aws-sdk-java-v2/blob/93269d4c0416d0f72e086774265847d6af0d54ec/services-custom/dynamodb-enhanced/src/test/java/software/amazon/awssdk/extensions/dynamodb/mappingclient/functionaltests/LocalDynamoDb.java) and ultimately adapting it to my own needs.

I'm going to work off of a template that I used in a previous blog post, [here is the source code on Github](https://github.com/nfisher23/webflux-and-dynamo).

## Configuring an embedded Dynamo instance

To start, to make it "cross platform" you'll need to do some funky things in your pom file. First, ensure that you're pointing to the correct maven instance by adding the dynamo repository:

```xml
    <repositories>
        <repository>
            <id>dynamodblocal</id>
            <name>AWS DynamoDB Local Release Repository</name>
            <url>https://s3-us-west-2.amazonaws.com/dynamodb-local/release</url>
        </repository>
    </repositories>

```

The actual dependencies you'll need seem to be basically these two:

```xml
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>DynamoDBLocal</artifactId>
            <version>1.13.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>com.almworks.sqlite4java</groupId>
            <artifactId>sqlite4java</artifactId>
            <version>1.0.392</version>
            <scope>test</scope>
        </dependency>

```

And now is where things might get a little weird. We need to pass in a system property variable for sqlite, which embedded dynamo is using under the hood, and add a dynamo package to the manifest. So first you'll add two plugin configs:

```xml
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-dependency-plugin</artifactId>
                <executions>
                    <execution>
                        <id>copy</id>
                        <phase>test-compile</phase>
                        <goals>
                            <goal>copy-dependencies</goal>
                        </goals>
                        <configuration>
                            <includeScope>test</includeScope>
                            <includeTypes>so,dll,dylib</includeTypes>
                            <outputDirectory>${project.build.directory}/native-libs</outputDirectory>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-jar-plugin</artifactId>
                <configuration>
                    <archive>
                        <manifestEntries>
                            <Automatic-Module-Name>software.amazon.awssdk.enhanced.dynamodb</Automatic-Module-Name>
                        </manifestEntries>
                    </archive>
                </configuration>
            </plugin>

```

Then some plugin management config:

```xml
        <pluginManagement>
            <plugins>
                <plugin>
                    <groupId>org.apache.maven.plugins</groupId>
                    <artifactId>maven-surefire-plugin</artifactId>
                    <configuration>
                        <systemPropertyVariables>
                            <sqlite4java.library.path>${project.build.directory}/native-libs</sqlite4java.library.path>
                        </systemPropertyVariables>
                    </configuration>
                </plugin>
            </plugins>
        </pluginManagement>

```

Now, on my machine, which is running linux mint, i was able to get this code to run and pass:

```java
public class PhoneServiceTest {

    private static DynamoDBProxyServer dynamoProxy;

    private static int port;

    private static int getFreePort() {
        try {
            ServerSocket socket = new ServerSocket(0);
            int port = socket.getLocalPort();
            socket.close();
            return port;
        } catch (IOException ioe) {
            throw new RuntimeException(ioe);
        }
    }

    @BeforeAll
    public static void setupDynamo() {
        port = getFreePort();
        try {
            dynamoProxy = ServerRunner.createServerFromCommandLineArgs(new String[]{
                    "-inMemory",
                    "-port",
                    Integer.toString(port)
            });
            dynamoProxy.start();
        } catch (Exception e) {
            throw new RuntimeException();
        }
    }

    @AfterAll
    public static void teardownDynamo() {
        try {
            dynamoProxy.stop();
        } catch (Exception e) {
            throw new RuntimeException();
        }
    }

    @Test
    public void testStuff() throws Exception {
        DynamoDbAsyncClient client = DynamoDbAsyncClient.builder()
                .region(Region.US_EAST_1)
                .endpointOverride(URI.create("http://localhost:" + port))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create("FAKE", "FAKE")))
                .build();

        ListTablesResponse listTablesResponse = client.listTables().get();

        assertThat(listTablesResponse.tableNames().size()).isEqualTo(0);

        client.createTable(CreateTableRequest.builder()
                .keySchema(
                        KeySchemaElement.builder().keyType(KeyType.HASH).attributeName("Company").build(),
                        KeySchemaElement.builder().keyType(KeyType.RANGE).attributeName("Model").build()
                )
                .attributeDefinitions(
                        AttributeDefinition.builder().attributeName("Company").attributeType(ScalarAttributeType.S).build(),
                        AttributeDefinition.builder().attributeName("Model").attributeType(ScalarAttributeType.S).build()
                )
                .provisionedThroughput(ProvisionedThroughput.builder().readCapacityUnits(100L).writeCapacityUnits(100L).build())
                .tableName("Phones")
                .build())
                .get();

        ListTablesResponse listTablesResponseAfterCreation = client.listTables().get();

        assertThat(listTablesResponseAfterCreation.tableNames().size()).isEqualTo(1);
    }
}

```

As seems pretty obvious here, we're starting up dynamo before we run our test, we are creating a tale with a hash and range key named **Phones**, then we are verifying that the table was created by listing all the tables \[there should be one table after we create it, somewhat obviously\]. This test passes for me and is good enough to get started with.

You might want to take that example demonstrating it in github if you're having trouble getting this to work on your OS, since this solution doesn't seem to have the abstractions setup just yet. Otherwise, I am at least happy this appears to be working for now on my box.
