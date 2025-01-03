---
title: "DynamoDB and Spring Boot Webflux - A Working Introduction"
date: 2020-07-18T23:07:05
draft: false
tags: [java, spring, aws, dynamodb, webflux]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo).

The [latest AWS SDK for java](https://docs.aws.amazon.com/sdk-for-java/v2/developer-guide/welcome.html) uses a reactive client to send requests to various AWS services, including DynamoDB. Reactive programming is ultimately more robust at the edges--once you start experiencing latency anywhere in your stack, if your tech is not reactive, you&#39;re going to have a significantly worse time than if it were.

This post was an experiment to get dynamo and spring boot webflux to play nice with each other.

## Bootstrap the Project

If you go to [the sprint boot initializr](https://start.spring.io/) and create a new project with the reactive web option, you can then setup your maven dependencies to look something like this:

```xml
&lt;?xml version=&#34;1.0&#34; encoding=&#34;UTF-8&#34;?&gt;
&lt;project xmlns=&#34;http://maven.apache.org/POM/4.0.0&#34; xmlns:xsi=&#34;http://www.w3.org/2001/XMLSchema-instance&#34;
         xsi:schemaLocation=&#34;http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd&#34;&gt;
    &lt;modelVersion&gt;4.0.0&lt;/modelVersion&gt;
    &lt;parent&gt;
        &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
        &lt;artifactId&gt;spring-boot-starter-parent&lt;/artifactId&gt;
        &lt;version&gt;2.3.1.RELEASE&lt;/version&gt;
        &lt;relativePath/&gt; &lt;!-- lookup parent from repository --&gt;
    &lt;/parent&gt;
    &lt;groupId&gt;com.nickolasfisher&lt;/groupId&gt;
    &lt;artifactId&gt;reactivedynamo&lt;/artifactId&gt;
    &lt;version&gt;1&lt;/version&gt;
    &lt;name&gt;reactivedynamo&lt;/name&gt;
    &lt;description&gt;Reactive Dynamo Tinkering&lt;/description&gt;

    &lt;properties&gt;
        &lt;java.version&gt;11&lt;/java.version&gt;
    &lt;/properties&gt;
    &lt;dependencyManagement&gt;
        &lt;dependencies&gt;
            &lt;dependency&gt;
                &lt;groupId&gt;software.amazon.awssdk&lt;/groupId&gt;
                &lt;artifactId&gt;bom&lt;/artifactId&gt;
                &lt;version&gt;2.13.7&lt;/version&gt;
                &lt;type&gt;pom&lt;/type&gt;
                &lt;scope&gt;import&lt;/scope&gt;
            &lt;/dependency&gt;
        &lt;/dependencies&gt;
    &lt;/dependencyManagement&gt;

    &lt;dependencies&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-actuator&lt;/artifactId&gt;
        &lt;/dependency&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-webflux&lt;/artifactId&gt;
        &lt;/dependency&gt;

        &lt;dependency&gt;
            &lt;groupId&gt;software.amazon.awssdk&lt;/groupId&gt;
            &lt;artifactId&gt;dynamodb&lt;/artifactId&gt;
        &lt;/dependency&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-test&lt;/artifactId&gt;
            &lt;scope&gt;test&lt;/scope&gt;
            &lt;exclusions&gt;
                &lt;exclusion&gt;
                    &lt;groupId&gt;org.junit.vintage&lt;/groupId&gt;
                    &lt;artifactId&gt;junit-vintage-engine&lt;/artifactId&gt;
                &lt;/exclusion&gt;
            &lt;/exclusions&gt;
        &lt;/dependency&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;io.projectreactor&lt;/groupId&gt;
            &lt;artifactId&gt;reactor-test&lt;/artifactId&gt;
            &lt;scope&gt;test&lt;/scope&gt;
        &lt;/dependency&gt;
    &lt;/dependencies&gt;

    &lt;build&gt;
        &lt;plugins&gt;
            &lt;plugin&gt;
                &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
                &lt;artifactId&gt;spring-boot-maven-plugin&lt;/artifactId&gt;
            &lt;/plugin&gt;
        &lt;/plugins&gt;
    &lt;/build&gt;

&lt;/project&gt;

```

The two important dependencies here are v2 of the AWS SDK and spring webflux.

You will want to set up your local DynamoDB environment, you can refer to [a previous post I created on that subject to help you out there](https://nickolasfisher.com/blog/DynamoDB-Basics-A-Hands-On-Tutorial), and we can then configure our AWS SDK to point to that for the purposes of this tutorial:

```java
@Configuration
public class Config {

    @Bean
    public DynamoDbAsyncClient dynamoDbAsyncClient() {
        return DynamoDbAsyncClient.builder()
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(&#34;FAKE&#34;, &#34;FAKE&#34;)))
                .region(Region.US_WEST_2)
                .endpointOverride(URI.create(&#34;http://localhost:8000&#34;))
                .build();
    }
}

```

**Important Note:** the AWS credentials and region in this config need to match the credentials that were set when you created your DynamoDB table to work with locally. The local DynamoDB container actually cares about them and will say that a table is not found if the credentials do not match.

Continuing with the last post, we&#39;re going to reuse the **Phones** table, which has a partition key that was **Company** and a range key of **Model**. So we have to provide at least that information in a put request to Dynamo to get the data persisted.

Our data model in spring boot is pretty straightforward. This generic template, including types:

```json
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

```

Can be pretty easily digested into a POJO:

```java
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
public class Phone {
    private String company;
    private String model;
    private List&lt;String&gt; colors;
    private Integer size;

... getters and setters ...

}

```

I elected to use handlers rather than using the more familiar Spring Boot annotations. The biggest issue I had was that I could not find a clean way to customize the response code \[Edit: I figured it out like twenty minutes after I wrote this, [here&#39;s the follow up blog post](https://nickolasfisher.com/blog/How-to-Return-a-Response-Entity-in-Spring-Boot-Webflux)\]. Here is some code that creates (PUTs) a new item and also allows you to read an item by the company and model name:

```java
@Component
public class PhoneHandler {

    public static final String PHONES_TABLENAME = &#34;Phones&#34;;
    public static final String COMPANY = &#34;Company&#34;;
    public static final String MODEL = &#34;Model&#34;;
    public static final String COLORS = &#34;Colors&#34;;
    public static final String SIZE = &#34;Size&#34;;

    private final DynamoDbAsyncClient dynamoDbAsyncClient;

    public PhoneHandler(DynamoDbAsyncClient dynamoDbAsyncClient) {
        this.dynamoDbAsyncClient = dynamoDbAsyncClient;
    }

    public Mono&lt;ServerResponse&gt; createPhoneHandler(ServerRequest serverRequest) {
        return serverRequest.bodyToMono(Phone.class).flatMap(phone -&gt; {
            Map&lt;String, AttributeValue&gt; item = new HashMap&lt;&gt;();
            item.put(COMPANY, AttributeValue.builder().s(phone.getCompany()).build());
            item.put(MODEL, AttributeValue.builder().s(phone.getModel()).build());
            item.put(COLORS, AttributeValue.builder().ss(phone.getColors()).build());
            if (phone.getSize() != null) {
                item.put(SIZE, AttributeValue.builder().n(phone.getSize().toString()).build());
            }

            PutItemRequest putItemRequest = PutItemRequest.builder().tableName(PHONES_TABLENAME).item(item).build();

            return Mono.fromCompletionStage(dynamoDbAsyncClient.putItem(putItemRequest))
                    .flatMap(putItemResponse -&gt; ServerResponse.ok().build());
        });
    }

    public Mono&lt;ServerResponse&gt; getSinglePhoneHandler(ServerRequest serverRequest) {
        String companyName = serverRequest.pathVariable(&#34;company-name&#34;);
        String modelName = serverRequest.pathVariable(&#34;model-name&#34;);

        Map&lt;String, AttributeValue&gt; getSinglePhoneItemRequest = new HashMap&lt;&gt;();
        getSinglePhoneItemRequest.put(COMPANY, AttributeValue.builder().s(companyName).build());
        getSinglePhoneItemRequest.put(MODEL, AttributeValue.builder().s(modelName).build());
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(PHONES_TABLENAME)
                .key(getSinglePhoneItemRequest)
                .build();

        CompletableFuture&lt;GetItemResponse&gt; item = dynamoDbAsyncClient.getItem(getItemRequest);
        return Mono.fromCompletionStage(item)
                .flatMap(getItemResponse -&gt; {
                    if (!getItemResponse.hasItem()) {
                        return ServerResponse.notFound().build();
                    }
                    Phone phone = new Phone();
                    phone.setColors(getItemResponse.item().get(COLORS).ss());
                    phone.setCompany(getItemResponse.item().get(COMPANY).s());
                    String stringSize = getItemResponse.item().get(SIZE).n();
                    phone.setSize(stringSize == null ? null : Integer.valueOf(stringSize));
                    phone.setModel(getItemResponse.item().get(MODEL).s());
                    return ServerResponse.ok()
                            .contentType(MediaType.APPLICATION_JSON)
                            .body(BodyInserters.fromValue(phone));
                });
    }
}

```

Handlers are pretty straightforward, they just take a request interface and respond with a response interface wrapped in a Mono. To actually make use of these we will have to register some more code to map a route to the function \[I put this back in **Config.java**\]:

```java
    @Bean
    public RouterFunction&lt;ServerResponse&gt; getPhoneRoutes(PhoneHandler phoneHandler) {
        return route(RequestPredicates.PUT(&#34;/phone&#34;), phoneHandler::createPhoneHandler)
                .andRoute(RequestPredicates.GET(&#34;/company/{company-name}/model/{model-name}/phone&#34;), phoneHandler::getSinglePhoneHandler);
    }

```

Finally, if you start up the application, then run a bit of bash to test it you should be able to see it in action:

```bash
#!/bin/bash
PHONE_TEMPLATE=$(cat &lt;&lt;&#39;EOF&#39;
{
    &#34;company&#34;: &#34;Nokia&#34;,
    &#34;model&#34;: &#34;1998 dumb phone&#34;,
    &#34;colors&#34;: [
        &#34;Red&#34;,
        &#34;Silver&#34;
    ],
    &#34;size&#34;: 19
}
EOF
)

NOKIA=$(printf &#34;$PHONE_TEMPLATE&#34;)

# create a new object using the template defined above
curl -v -XPUT localhost:8080/phone -H &#34;Content-Type: application/json&#34; --data &#34;$NOKIA&#34;

# view the object
curl -v -XGET &#34;http://localhost:8080/company/Nokia/model/1998%20dumb%20phone/phone&#34;

# you should see a 404 here, the object does not exist:
curl -v -XGET &#34;http://localhost:8080/company/Nokia/model/not-real/phone&#34;

```

And with that, you should be in a good place to start.
