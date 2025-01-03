---
title: "How to Use Spring's Aspect Oriented Programming to log all Public Methods"
date: 2018-11-18T14:40:55
draft: false
tags: [java, aspect oriented programming, spring]
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/spring-aop-universal-public-logger).

[Aspect Oriented Programming In Spring](https://docs.spring.io/spring/docs/2.5.x/reference/aop.html) is a clever way to reduce code duplication, by taking a different approach than traditional tools like dependency injection or inheritance. Cross cutting concerns like security and logging can permeate a code base and make maintainability a nightmare unless properly taken care of, and aspect oriented programming is one way to properly take care of that, when used appropriately. This post will illustrate how to get started with a transparent way to log without cluttering up business logic.

The provided link above gives a thorough and concise introduction to the strange AOP terminologies that get introduced when you go down this path, and you should read through that first before moving on.

The things you'll need to get aspects enabled in your project are:

- A reference in your pom.xml (if using maven) or your build.gradle (if using gradle). E.g. for spring boot and maven:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aop</artifactId>
</dependency>
```

- An aspect annotation above a bean definition. In our case, we can demonstrate an aspect that uses around-advice like so:


```java
@Aspect
@Component
public class LoggerAspect {

    @Around("execution(public * *(..)) &amp;&amp; within(com.nickolasfisher.aspectdemo..*)")
    private Object logAroundEveryPublicMethod(ProceedingJoinPoint pjp) throws Throwable {
        System.out.println("\n-----------beginning around advice---------");

        System.out.println("arguments: " + Arrays.stream(pjp.getArgs()).map(Object::toString).collect(Collectors.toList()));
        System.out.println("pointcut as long string: " + pjp.toLongString());
        System.out.println("method signature: " + pjp.getSignature());
        System.out.println("target class: " + pjp.getTarget().toString());
        System.out.println("class in use: " + pjp.getSourceLocation().getWithinType());

        Object returnedVal = pjp.proceed();

        System.out.println("returned value: " + returnedVal);
        System.out.println("---------around advice concluded---------\n");
        return returnedVal;
    }
}
```

Here, the @Around(..) annotation runs this block of code around any method that falls into our pointcut definition. Our pointcut definition is

```java
execution(public * *(..)) &amp;&amp; within(com.nickolasfisher.aspectdemo..*)
```

Which says "any public method" and "within the package com.nickolasfisher.aspectdemo". When both of these criteria are met, then the aspect will execute. When we call pjp.proceed(), we run the method that we are "decorating", and we have to return a value from this method, which then gets processed in the application. You could theoretically return something different than what the method itself executed, or call the method multiple times--though I would recommend you don't unless you have a very compelling reason, as that would make debugging a nightmare for future you or for a teammate.

This works on both interfaces and classes. To demonstrate, we'll create a very simple interface:

```java
public interface InterfaceToAspectOn {
    void emptyMethod1();

    void emptyMethod2();

    String methodThatReturns(String input);
}
```

Which we'll implement like so:

```java
@Component
public class ClassImplementingInterface implements InterfaceToAspectOn {
    @Override
    public void emptyMethod1() {
        System.out.println("inside emptyMethod1");
    }

    @Override
    public void emptyMethod2() {
        System.out.println("inside emptyMethod2");
    }

    @Override
    public String methodThatReturns(String input) {
        System.out.println("method that returns with input value: " + input);
        return "some returned string";
    }
}
```

We'll also create a standalone class to demonstrate an interface-less aspect execution:

```java
@Component
public class StandaloneClass {
    public void doSomethingInOtherClass() {
        System.out.println("in a standalone class method");
    }
}

```

We can bring all of this together in our Spring Boot 2.0+ application by using Spring's [PostConstruct](https://docs.spring.io/spring/docs/4.3.20.RELEASE/spring-framework-reference/htmlsingle/#beans-postconstruct-and-predestroy-annotations):

```java
@Component
public class PostConstructRunner {

    private final InterfaceToAspectOn interfaceToAspectOn;

    private final StandaloneClass standaloneClass;

    public PostConstructRunner(InterfaceToAspectOn interfaceToAspectOn, StandaloneClass standaloneClass) {
        this.interfaceToAspectOn = interfaceToAspectOn;
        this.standaloneClass = standaloneClass;
    }

    @PostConstruct
    public void runOnce() {
        System.out.println("running method after context loaded");

        interfaceToAspectOn.emptyMethod1();
        interfaceToAspectOn.emptyMethod2();

        String val = interfaceToAspectOn.methodThatReturns("some string input value");
        System.out.println("returned value inside post construct: " + val);

        standaloneClass.doSomethingInOtherClass();

        System.out.println("post construct method concluded");
    }
}

```

When you run this application, you should see printed output that contains text like so:

```bash
-----------beginning around advice---------
arguments: [some string input value]
pointcut as long string: execution(public java.lang.String com.nickolasfisher.aspectdemo.classes.ClassImplementingInterface.methodThatReturns(java.lang.String))
method signature: String com.nickolasfisher.aspectdemo.classes.ClassImplementingInterface.methodThatReturns(String)
target class: com.nickolasfisher.aspectdemo.classes.ClassImplementingInterface@6e2aa843
class in use: class com.nickolasfisher.aspectdemo.classes.ClassImplementingInterface
method that returns with input value: some string input value
returned value: some returned string
---------around advice concluded---------
```

While you can and should customize logs to fit your particular situation, you can use this template to get started in that process.
