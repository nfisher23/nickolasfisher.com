---
title: "How to Prevent DEBUG Logging by Test Containers when Running Unit Tests in Java"
date: 2021-04-01T00:00:00
draft: false
---

I have been playing around with test containers lately \[ [redis test containers for testing lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux) and [dynamodb test containers for testing the AWS SDK 2.0](https://nickolasfisher.com/blog/Setup-and-Use-a-DynamoDB-Test-Container-with-the-AWS-Java-SDK-20), to be specific\], and I found soon after using them that I was getting by default a stream of DEBUG level logs whenever I ran my test suite. This was annoying, so I went digging for a solution.

At least when using spring boot, the answer is that test containers uses logback by default, and you need to add a **logback-test.xml** file to your **src/test/resources** directory that looks like this:

``` java
&lt;configuration&gt;
    &lt;appender name=&#34;STDOUT&#34; class=&#34;ch.qos.logback.core.ConsoleAppender&#34;&gt;
        &lt;encoder&gt;
            &lt;pattern&gt;%d{HH:mm:ss.SSS} [%thread] %-5level %logger - %msg%n&lt;/pattern&gt;
        &lt;/encoder&gt;
    &lt;/appender&gt;

    &lt;root level=&#34;info&#34;&gt;
        &lt;appender-ref ref=&#34;STDOUT&#34;/&gt;
    &lt;/root&gt;

    &lt;logger name=&#34;org.testcontainers&#34; level=&#34;INFO&#34;/&gt;
    &lt;logger name=&#34;com.github.dockerjava&#34; level=&#34;WARN&#34;/&gt;
&lt;/configuration&gt;

```

This is buried in the documentation about the [recommended logback configuration for test containers](https://www.testcontainers.org/supported_docker_environment/logging_config/), though nothing about a global DEBUG level takeover if you leave it out is mentioned at least as of now.


