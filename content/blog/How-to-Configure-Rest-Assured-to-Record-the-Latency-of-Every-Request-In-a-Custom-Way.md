---
title: "How to Configure Rest Assured to Record the Latency of Every Request In a Custom Way"
date: 2020-06-13T21:06:52
draft: false
tags: [java, maven, testing, rest assured]
---

Sample code associated with this post can be found [on Github](https://github.com/nfisher23/examples-testing-stuff).

[Rest Assured](https://github.com/rest-assured/rest-assured/wiki/Usage) is a library that makes it easy to write api based automated tests in java. Recently I needed to find a way to record the latency of each request as well as some metadata about it \[request path, method, things of that nature\]. I found a nice way to do this with [rest assured filters](https://github.com/rest-assured/rest-assured/wiki/Usage#filters), and I'm going to share that with you in this article.

You can get this started by bootstrapping a maven project:

```
mvn archetype:generate -DarchetypeGroupId=org.apache.maven.archetypes -DarchetypeArtifactId=maven-archetype-quickstart -DarchetypeVersion=1.4
```

Follow the prompts, set it up to be whatever you want.

You will then need to add a couple of dependencies, I'll just list out all of them here:

```xml
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.11</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>io.rest-assured</groupId>
      <artifactId>rest-assured</artifactId>
      <version>3.0.0</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>jakarta.xml.bind</groupId>
      <artifactId>jakarta.xml.bind-api</artifactId>
      <version>2.3.2</version>
    </dependency>
    <dependency>
      <groupId>org.glassfish.jaxb</groupId>
      <artifactId>jaxb-runtime</artifactId>
      <version>2.3.2</version>
    </dependency>
  </dependencies>

```

I'll write out a couple of simple examples so I can demonstrate how to best do this:

```java
    @Test
    public void getGoogleHomepage() {
        RestAssured.with()
                .baseUri("https://www.google.com")
                .get()
                .then()
                .statusCode(200);
    }

    @Test
    public void getDuckDuckGoHomepage() {
        RestAssured.with()
                .baseUri("https://duckduckgo.com")
                .get()
                .then()
                .statusCode(200);
    }

```

Once you have these in place, you can run:

```
mvn test

```

And, provided google and duck duck go have their services available, you will see a couple of passing tests.

### Track Latency With a Filter

Now let's say we have a bunch of tests and we want to track the latency of each one, and further let's say we have to send that to a file in some form of custom logic. We can execute whatever custom logic we want with a [filter](https://github.com/rest-assured/rest-assured/wiki/Usage#filters).

```java
    static {
        RestAssured.requestSpecification = RestAssured.with()
                .filter(new Filter() {
            @Override
            public Response filter(FilterableRequestSpecification filterableRequestSpecification,
                                   FilterableResponseSpecification filterableResponseSpecification,
                                   FilterContext filterContext) {
                StopWatch sw = new StopWatch();
                sw.start();
                Response response = filterContext.next(filterableRequestSpecification, filterableResponseSpecification);
                sw.stop();
                System.out.println("time: " + sw.getTime());
                return response;
            }
        });
    }

```

If I go to run this, I'll see a couple of times in milliseconds get printed out:

```
$ mvn test
...
time: 1839
time: 325

```

This brings up an important point, and that's [JVM warmups](https://stackoverflow.com/questions/36198278/why-does-the-jvm-require-warmup). This specific type of analysis is really only going to be useful if you have a lot of tests, then it will tend to average itself out. But with only two tests, tracking latency like this is not particularly useful.
