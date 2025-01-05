---
title: "DynamoDB and Spring Boot Webflux - A Working Introduction"
date: 2020-07-18T23:07:05
draft: false
tags: [java, spring, aws, dynamodb, webflux]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/webflux-and-dynamo).

The [latest AWS SDK for java](https://docs.aws.amazon.com/sdk-for-java/v2/developer-guide/welcome.html) uses a reactive client to send requests to various AWS services, including DynamoDB. Reactive programming is ultimately more robust at the edges--once you start experiencing latency anywhere in your stack, if your tech is not reactive, you're going to have a significantly worse time than if it were.

This post was an experiment to get dynamo and spring boot webflux to play nice with each other.

## Bootstrap the Project

If you go to [the sprint boot initializr](https://start.spring.io/) and create a new project with the reactive web option, you can then setup your maven dependencies to look something like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>2.3.1.RELEASE</version>
        <relativePath/> <!-- lookup parent from repository -->
    </parent>
    <groupId>com.nickolasfisher</groupId>
    <artifactId>reactivedynamo</artifactId>
    <version>1</version>
    <name>reactivedynamo</name>
    <description>Reactive Dynamo Tinkering</description>

    <properties>
        <java.version>11</java.version>
    </properties>
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>software.amazon.awssdk</groupId>
                <artifactId>bom</artifactId>
                <version>2.13.7</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-webflux</artifactId>
        </dependency>

        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>dynamodb</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
            <exclusions>
                <exclusion>
                    <groupId>org.junit.vintage</groupId>
                    <artifactId>junit-vintage-engine</artifactId>
                </exclusion>
            </exclusions>
        </dependency>
        <dependency>
            <groupId>io.projectreactor</groupId>
            <artifactId>reactor-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>

</project>

```

The two important dependencies here are v2 of the AWS SDK and spring webflux.

You will want to set up your local DynamoDB environment, you can refer to [a previous post I created on that subject to help you out there](https://nickolasfisher.com/blog/dynamodb-basics-a-hands-on-tutorial), and we can then configure our AWS SDK to point to that for the purposes of this tutorial:

```java
@Configuration
public class Config {

    @Bean
    public DynamoDbAsyncClient dynamoDbAsyncClient() {
        return DynamoDbAsyncClient.builder()
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create("FAKE", "FAKE")))
                .region(Region.US_WEST_2)
                .endpointOverride(URI.create("http://localhost:8000"))
                .build();
    }
}

```

**Important Note:** the AWS credentials and region in this config need to match the credentials that were set when you created your DynamoDB table to work with locally. The local DynamoDB container actually cares about them and will say that a table is not found if the credentials do not match.

Continuing with the last post, we're going to reuse the **Phones** table, which has a partition key that was **Company** and a range key of **Model**. So we have to provide at least that information in a put request to Dynamo to get the data persisted.

Our data model in spring boot is pretty straightforward. This generic template, including types:

```json
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

```

Can be pretty easily digested into a POJO:

```java
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
public class Phone {
    private String company;
    private String model;
    private List<String> colors;
    private Integer size;

... getters and setters ...

}

```

I elected to use handlers rather than using the more familiar Spring Boot annotations. The biggest issue I had was that I could not find a clean way to customize the response code \[Edit: I figured it out like twenty minutes after I wrote this, [here's the follow up blog post](https://nickolasfisher.com/blog/how-to-return-a-response-entity-in-spring-boot-webflux)\]. Here is some code that creates (PUTs) a new item and also allows you to read an item by the company and model name:

```java
@Component
public class PhoneHandler {

    public static final String PHONES_TABLENAME = "Phones";
    public static final String COMPANY = "Company";
    public static final String MODEL = "Model";
    public static final String COLORS = "Colors";
    public static final String SIZE = "Size";

    private final DynamoDbAsyncClient dynamoDbAsyncClient;

    public PhoneHandler(DynamoDbAsyncClient dynamoDbAsyncClient) {
        this.dynamoDbAsyncClient = dynamoDbAsyncClient;
    }

    public Mono<ServerResponse> createPhoneHandler(ServerRequest serverRequest) {
        return serverRequest.bodyToMono(Phone.class).flatMap(phone -> {
            Map<String, AttributeValue> item = new HashMap<>();
            item.put(COMPANY, AttributeValue.builder().s(phone.getCompany()).build());
            item.put(MODEL, AttributeValue.builder().s(phone.getModel()).build());
            item.put(COLORS, AttributeValue.builder().ss(phone.getColors()).build());
            if (phone.getSize() != null) {
                item.put(SIZE, AttributeValue.builder().n(phone.getSize().toString()).build());
            }

            PutItemRequest putItemRequest = PutItemRequest.builder().tableName(PHONES_TABLENAME).item(item).build();

            return Mono.fromCompletionStage(dynamoDbAsyncClient.putItem(putItemRequest))
                    .flatMap(putItemResponse -> ServerResponse.ok().build());
        });
    }

    public Mono<ServerResponse> getSinglePhoneHandler(ServerRequest serverRequest) {
        String companyName = serverRequest.pathVariable("company-name");
        String modelName = serverRequest.pathVariable("model-name");

        Map<String, AttributeValue> getSinglePhoneItemRequest = new HashMap<>();
        getSinglePhoneItemRequest.put(COMPANY, AttributeValue.builder().s(companyName).build());
        getSinglePhoneItemRequest.put(MODEL, AttributeValue.builder().s(modelName).build());
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(PHONES_TABLENAME)
                .key(getSinglePhoneItemRequest)
                .build();

        CompletableFuture<GetItemResponse> item = dynamoDbAsyncClient.getItem(getItemRequest);
        return Mono.fromCompletionStage(item)
                .flatMap(getItemResponse -> {
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
    public RouterFunction<ServerResponse> getPhoneRoutes(PhoneHandler phoneHandler) {
        return route(RequestPredicates.PUT("/phone"), phoneHandler::createPhoneHandler)
                .andRoute(RequestPredicates.GET("/company/{company-name}/model/{model-name}/phone"), phoneHandler::getSinglePhoneHandler);
    }

```

Finally, if you start up the application, then run a bit of bash to test it you should be able to see it in action:

```bash
#!/bin/bash
PHONE_TEMPLATE=$(cat <<'EOF'
{
    "company": "Nokia",
    "model": "1998 dumb phone",
    "colors": [
        "Red",
        "Silver"
    ],
    "size": 19
}
EOF
)

NOKIA=$(printf "$PHONE_TEMPLATE")

# create a new object using the template defined above
curl -v -XPUT localhost:8080/phone -H "Content-Type: application/json" --data "$NOKIA"

# view the object
curl -v -XGET "http://localhost:8080/company/Nokia/model/1998%20dumb%20phone/phone"

# you should see a 404 here, the object does not exist:
curl -v -XGET "http://localhost:8080/company/Nokia/model/not-real/phone"

```

And with that, you should be in a good place to start.
