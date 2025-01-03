---
title: "Configuring an In Memory DynamoDB instance with Java for Integration Testing"
date: 2020-10-10T00:02:25
draft: false
tags: [java, reactive, aws, dynamodb, webflux]
---

While using the AWS SDK 2.0, which has support for reactive programming, it became clear that there was no straightforward support for an embedded dynamo db instance for testing. I spent a fair amount of time figuring it out by starting with [this github link](https://github.com/aws/aws-sdk-java-v2/blob/93269d4c0416d0f72e086774265847d6af0d54ec/services-custom/dynamodb-enhanced/src/test/java/software/amazon/awssdk/extensions/dynamodb/mappingclient/functionaltests/LocalDynamoDb.java) and ultimately adapting it to my own needs.

I&#39;m going to work off of a template that I used in a previous blog post, [here is the source code on Github](https://github.com/nfisher23/webflux-and-dynamo).

## Configuring an embedded Dynamo instance

To start, to make it &#34;cross platform&#34; you&#39;ll need to do some funky things in your pom file. First, ensure that you&#39;re pointing to the correct maven instance by adding the dynamo repository:

```xml
    &lt;repositories&gt;
        &lt;repository&gt;
            &lt;id&gt;dynamodblocal&lt;/id&gt;
            &lt;name&gt;AWS DynamoDB Local Release Repository&lt;/name&gt;
            &lt;url&gt;https://s3-us-west-2.amazonaws.com/dynamodb-local/release&lt;/url&gt;
        &lt;/repository&gt;
    &lt;/repositories&gt;

```

The actual dependencies you&#39;ll need seem to be basically these two:

```xml
        &lt;dependency&gt;
            &lt;groupId&gt;com.amazonaws&lt;/groupId&gt;
            &lt;artifactId&gt;DynamoDBLocal&lt;/artifactId&gt;
            &lt;version&gt;1.13.2&lt;/version&gt;
            &lt;scope&gt;test&lt;/scope&gt;
        &lt;/dependency&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;com.almworks.sqlite4java&lt;/groupId&gt;
            &lt;artifactId&gt;sqlite4java&lt;/artifactId&gt;
            &lt;version&gt;1.0.392&lt;/version&gt;
            &lt;scope&gt;test&lt;/scope&gt;
        &lt;/dependency&gt;

```

And now is where things might get a little weird. We need to pass in a system property variable for sqlite, which embedded dynamo is using under the hood, and add a dynamo package to the manifest. So first you&#39;ll add two plugin configs:

```xml
            &lt;plugin&gt;
                &lt;groupId&gt;org.apache.maven.plugins&lt;/groupId&gt;
                &lt;artifactId&gt;maven-dependency-plugin&lt;/artifactId&gt;
                &lt;executions&gt;
                    &lt;execution&gt;
                        &lt;id&gt;copy&lt;/id&gt;
                        &lt;phase&gt;test-compile&lt;/phase&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;copy-dependencies&lt;/goal&gt;
                        &lt;/goals&gt;
                        &lt;configuration&gt;
                            &lt;includeScope&gt;test&lt;/includeScope&gt;
                            &lt;includeTypes&gt;so,dll,dylib&lt;/includeTypes&gt;
                            &lt;outputDirectory&gt;${project.build.directory}/native-libs&lt;/outputDirectory&gt;
                        &lt;/configuration&gt;
                    &lt;/execution&gt;
                &lt;/executions&gt;
            &lt;/plugin&gt;
            &lt;plugin&gt;
                &lt;groupId&gt;org.apache.maven.plugins&lt;/groupId&gt;
                &lt;artifactId&gt;maven-jar-plugin&lt;/artifactId&gt;
                &lt;configuration&gt;
                    &lt;archive&gt;
                        &lt;manifestEntries&gt;
                            &lt;Automatic-Module-Name&gt;software.amazon.awssdk.enhanced.dynamodb&lt;/Automatic-Module-Name&gt;
                        &lt;/manifestEntries&gt;
                    &lt;/archive&gt;
                &lt;/configuration&gt;
            &lt;/plugin&gt;

```

Then some plugin management config:

```xml
        &lt;pluginManagement&gt;
            &lt;plugins&gt;
                &lt;plugin&gt;
                    &lt;groupId&gt;org.apache.maven.plugins&lt;/groupId&gt;
                    &lt;artifactId&gt;maven-surefire-plugin&lt;/artifactId&gt;
                    &lt;configuration&gt;
                        &lt;systemPropertyVariables&gt;
                            &lt;sqlite4java.library.path&gt;${project.build.directory}/native-libs&lt;/sqlite4java.library.path&gt;
                        &lt;/systemPropertyVariables&gt;
                    &lt;/configuration&gt;
                &lt;/plugin&gt;
            &lt;/plugins&gt;
        &lt;/pluginManagement&gt;

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
                    &#34;-inMemory&#34;,
                    &#34;-port&#34;,
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
                .endpointOverride(URI.create(&#34;http://localhost:&#34; &#43; port))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(&#34;FAKE&#34;, &#34;FAKE&#34;)))
                .build();

        ListTablesResponse listTablesResponse = client.listTables().get();

        assertThat(listTablesResponse.tableNames().size()).isEqualTo(0);

        client.createTable(CreateTableRequest.builder()
                .keySchema(
                        KeySchemaElement.builder().keyType(KeyType.HASH).attributeName(&#34;Company&#34;).build(),
                        KeySchemaElement.builder().keyType(KeyType.RANGE).attributeName(&#34;Model&#34;).build()
                )
                .attributeDefinitions(
                        AttributeDefinition.builder().attributeName(&#34;Company&#34;).attributeType(ScalarAttributeType.S).build(),
                        AttributeDefinition.builder().attributeName(&#34;Model&#34;).attributeType(ScalarAttributeType.S).build()
                )
                .provisionedThroughput(ProvisionedThroughput.builder().readCapacityUnits(100L).writeCapacityUnits(100L).build())
                .tableName(&#34;Phones&#34;)
                .build())
                .get();

        ListTablesResponse listTablesResponseAfterCreation = client.listTables().get();

        assertThat(listTablesResponseAfterCreation.tableNames().size()).isEqualTo(1);
    }
}

```

As seems pretty obvious here, we&#39;re starting up dynamo before we run our test, we are creating a tale with a hash and range key named **Phones**, then we are verifying that the table was created by listing all the tables \[there should be one table after we create it, somewhat obviously\]. This test passes for me and is good enough to get started with.

You might want to take that example demonstrating it in github if you&#39;re having trouble getting this to work on your OS, since this solution doesn&#39;t seem to have the abstractions setup just yet. Otherwise, I am at least happy this appears to be working for now on my box.
