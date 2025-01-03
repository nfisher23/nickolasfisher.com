---
title: "Use First Class Functions to Reduce Code Duplication In Java"
date: 2018-11-24T19:03:21
draft: false
tags: [java]
---

Often when we program, we find ourselves creating patterns, usually in the form of boilerplate code, that seem to always do the same thing. For example, let's say you have some logging logic that is non-trivial, and you want to make extra sure you don't blow up your main application while it's running, so you surround it with a try/catch block:

```java
    public void logSomething(List<String> stuffToLog) {
        try {
            log.info("stuff: " + String.join(",", stuffToLog));
        } catch (Exception e) {
            log.error("failed to log: " + e.toString());
        }
    }
```

Or maybe you just want to make sure that it's not null before you pass it in, so you validate that it's not null before loggging:

```java
    public void logSomethingElse(List<String> stuffToLog) {
        if (stuffToLog != null &amp;&amp; stuffToLog.size() > 0) {
            log.info("stuff: " + String.join(",", stuffToLog));
        }
    }
```

Let's say you have to do this a lot in your application. There are some pieces of business logic that, for the sake of being resilient, you want to surround in a try/catch and log any failures. You might write another method like this:

```java
    public void executeSomething(String value) {
        try {
            repository.persist(value);
        } catch (Exception e) {
            log.error("we failed to execute this code block: " + e.toString());
        }
    }
```

While it doesn't feel like it at first, _this is code duplication_, which is the root of all evil in non-trivial projects. When you, or some other programmer, later realizes that simply calling **e.toString()** doesn't give you enough information to adequately debug something (it's not), and you instead have to do some annoyingly fancy (thanks, Java) stuff to get the stack track to log:

```java
StringWriter sw = new StringWriter();
PrintWriter pw = new PrintWriter(sw);
e.printStackTrace(pw);
String actualStackTrace = sw.toString();

```

You now have to change the way you log exceptions everywhere in the application. You might say, "well, that's an easy fix. Just refactor the **log.info(..)** method into it's own **customLog(..)** method, and call that throughout your application."

That choice takes you one step closer, but it will only solve one of the forms of code duplication that is present in this example. _Surrounding everything with a try/catch block is duplication_. Let's say there's a particular type of custom defined exception that permeates your code called a **HolyCrudException**. That gets added later on in development, but you have to ensure that previously developed code handles that specific exception:

```java
    public void executeSomething(String value) {
        try {
            repository.persist(value);
        } catch (HolyCrudException e) {
            customLogError("HolyCrudException! This is seriously not good! Raising the alarms");
            raiseAlarm();
        }
        catch (Exception e) {
            customLogError("we failed to execute this code block: " + getStackTrace(e));
        }
    }

```

Well, now you have to go back to every try/catch block you've previously defined and change that too.

One very good solution to this problem in Java is taking full advantage of lamdbas to create **templates**, which leverages Java 8+ and its support for first-class functions. We can pass in a function like it's a variable, and the Java compiler silently makes an anonymous class for us under the hood. Templates are found extensively in the Spring libraries, notably [JdbcTemplate](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/jdbc/core/JdbcTemplate.html) and [RestTemplate](https://docs.spring.io/spring/docs/current/javadoc-api/org/springframework/web/client/RestTemplate.html). We can make our own templates easily by leveraging the extensive [Java library for Functional Interfaces](https://docs.oracle.com/javase/8/docs/api/java/util/function/package-summary.html). Here, we obviously want to run some method inside a try/catch block, and log certain types of exceptions, so we can create a method that takes a Runnable:

```java
    public void runInsideTryCatch(Runnable r) {
        try {
            r.run();
        } catch (HolyCrudException e) {
            log.error("HolyCrudException! This is seriously not good! Raising the alarms");
            raiseAlarm();
        }
        catch (Exception e) {
            log.error("we failed to execute this code block: " + e.toString());
        }
    }

```

And we can reuse this method whenever we want with a simple lambda expression:

```java
runInsideTryCatch(() -> repository.persist(value));
```

And:

```java
runInsideTryCatch(() -> customLogError("log something uber important"));
```

Another approach might be Aspect Oriented Programming, but the advantage of this approach is its transparency. AOP can often feel "magical," since a code block might be affected by an AOP framework behind the scenes. This approach clearly lays out its intention, and you can navigate to the **runInsideTryCatch(..)** method with a shortcut on your IDE.

I personally find this method of templating, and leveraging the passing around of functions as normal variables, extremely useful. Focusing on the new logic you want to introduce, rather than constantly rewriting boilerplate code, can make everything in your application more changeable and less prone to nasty bugs. One mistake should require one fix, and if it doesn't it usually means you have an opportunity to improve your skills.
