---
title: "How to Prevent DEBUG Logging by Test Containers when Running Unit Tests in Java"
date: 2021-04-24T20:35:47
draft: false
tags: [java, spring, testing]
---

I have been playing around with test containers lately \[ [redis test containers for testing lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux) and [dynamodb test containers for testing the AWS SDK 2.0](https://nickolasfisher.com/blog/Setup-and-Use-a-DynamoDB-Test-Container-with-the-AWS-Java-SDK-20), to be specific\], and I found soon after using them that I was getting by default a stream of DEBUG level logs whenever I ran my test suite. This was annoying, so I went digging for a solution.

At least when using spring boot, the answer is that test containers uses logback by default, and you need to add a **logback-test.xml** file to your **src/test/resources** directory that looks like this:

```java
<configuration>
    <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger - %msg%n</pattern>
        </encoder>
    </appender>

    <root level="info">
        <appender-ref ref="STDOUT"/>
    </root>

    <logger name="org.testcontainers" level="INFO"/>
    <logger name="com.github.dockerjava" level="WARN"/>
</configuration>

```

This is buried in the documentation about the [recommended logback configuration for test containers](https://www.testcontainers.org/supported_docker_environment/logging_config/), though nothing about a global DEBUG level takeover if you leave it out is mentioned at least as of now.
