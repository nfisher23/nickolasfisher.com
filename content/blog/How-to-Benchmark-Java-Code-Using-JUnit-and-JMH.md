---
title: "How to Benchmark Java Code Using JUnit and JMH"
date: 2018-11-10T12:28:58
draft: false
tags: [java, performance testing, jmh]
---

You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/jmh-junit-intro).

[JMH](https://openjdk.java.net/projects/code-tools/jmh/) is a lightweight code generator that can benchmark Java code. While many of the performance bottlenecks in today's world are related to network calls and/or database queries, it's still a good idea to understand the performance of our code at a lower level. In particular, by automating performance tests on our code, we can usually at least ensure that the performance was not accidentally made worse by some refactoring effort.

By insisting on running our JMH benchmarks in JUnit code, we can quickly and easily set up continuous integration. While this is not the "recommended" approach, in my experience it has been consistent in its results. Especially since this is best used as a learning tool, let's just get from zero to one as quickly as possible.

First, you'll need the maven dependency:

```xml
<dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-generator-annprocess</artifactId>
    <version>1.21</version>
    <scope>test</scope>
</dependency>

```

All you need is one JUnit test case, which will be the entry point for all of the benchmarks in your file:

```java
@Test
public void runBenchmarks() throws Exception {
    Options options = new OptionsBuilder()
            .include(this.getClass().getName() + ".*")
            .mode(Mode.AverageTime)
            .warmupTime(TimeValue.seconds(1))
            .warmupIterations(6)
            .threads(1)
            .measurementIterations(6)
            .forks(1)
            .shouldFailOnError(true)
            .shouldDoGC(true)
            .build();

    new Runner(options).run();
}

```

Be sure to configure the options as you see fit. The fluent API makes it all pretty intuitive. Do be careful if you're using OS resources, however, because if you have multiple threads running at the same time, then you will likely see inconsistent results as all the threads battle for the same resources.

Then, each benchmark case you want to run will be annotated with `@Benchmark`. For these examples, we are going to compare the performance difference between using a `StringBuilder` and concatenating Strings. Since Strings are immutable, when we choose to concatenate them, the runtime engine reinitializes another String and populates it with each character that came before it. That is, something like `str1 = str1 + "something";` would create a new string by iterating through each character in `str1` and "something".

A `StringBuilder` fixes all of this, because it creates an ArrayList that takes existing strings and populates them into the ArrayList. When we are done, it concatenates everything in the data structure one time, which is much less costly. Here we will run the sub-optimal version described above:

```java
private static String hello = "not another hello world";

@Benchmark
@OutputTimeUnit(TimeUnit.MILLISECONDS)
public void stringsWithoutStringBuilder() throws Exception {
    String hellos = "";
    for (int i = 0; i < 1000; i++) {
        hellos += hello;
        if (i != 999) {
            hellos += "\n";
        }
    }
    assertTrue(hellos.startsWith((hello + "\n")));
}

```

And here, we show the method that uses `StringBuilder`:

```java
@Benchmark
@OutputTimeUnit(TimeUnit.MILLISECONDS)
public void stringsWithStringBuilder() throws Exception {
    StringBuilder hellosBuilder = new StringBuilder();
    for (int i = 0; i < 1000; i++) {
        hellosBuilder.append(hello);
        if (i != 999) {
            hellosBuilder.append("\n");
        }
    }
    assertTrue(hellosBuilder.toString().startsWith((hello + "\n")));
}

```

The JMH benchmarks output the following on my machine (be sure to get the code and try them yourself):

```bash
Benchmark                                                   Mode  Cnt  Score   Error  Units
JmhJunitSampleApplicationTests.stringsWithStringBuilder     avgt    6  0.031 ± 0.005  ms/op
JmhJunitSampleApplicationTests.stringsWithoutStringBuilder  avgt    6  3.738 ± 0.614  ms/op
```

As expected, concatenating the strings each time was much more costly, and in this case was ~120 times slower.

For details on how to take full advantage of the JMH framework, be sure to read through the [samples](https://hg.openjdk.java.net/code-tools/jmh/file/tip/jmh-samples/src/main/java/org/openjdk/jmh/samples/), which double as well explained tutorials.
