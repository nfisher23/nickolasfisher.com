---
title: "The Java Stream API: Primitive Streams"
date: 2018-10-21T19:49:49
draft: false
tags: [java, java stream api]
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

While Streams in Java would typically be used on POJO or POJO-like data structures, Java also lets us deal directly with primitive type streams.
Thanks to Java&#39;s type erasure, something like Stream&lt;int&gt; would not work, as the type argument must be an Object.

However, the smaller and more focused primitive type streams are still quite useful. We can get a summary statistics of any IntStream like so:

```java
@Test
public void intStream_simpleEx() {
    IntStream intStream = IntStream.of(1,4,5,8,9,10);

    IntSummaryStatistics stats = intStream.summaryStatistics();

    assertEquals(10, stats.getMax());
}

```

We can do the same with a DoubleStream:

```java
@Test
public void doubleStream_simpleEx() {
    DoubleStream doubleStream = DoubleStream.of(1.0, 2.5, 3.5, 6.5, 8.0);

    DoubleSummaryStatistics stats = doubleStream.summaryStatistics();

    assertEquals(5, stats.getCount());
    assertEquals(1.0, stats.getMin(), .01);
}

```

And with a LongStream:

```java
@Test
public void longStream_simpleEx() {
    LongStream longStream = LongStream.of(100, 101, 102, 103);

    long[] longs = longStream.filter(l -&gt; l &gt;= 101).toArray();

    assertEquals(longs[0], 101);
}

```

We can turn a Stream&lt;?&gt; into a primitive stream by calling the corresponding mapping function, e.g. mapToInt(..). Here, we&#39;ll map a Stream&lt;SimplePair&gt;, where the SimplePair object just has a name (String) and id (int) into an IntStream:

```java
@Test
public void mapToIntStream() {
    IntStream nameLengths = pairs.stream().mapToInt(sp -&gt; sp.getName().length());

    IntSummaryStatistics stats = nameLengths.summaryStatistics();

    assertEquals(5, stats.getMin());
}

```

We can go the other way any time we want to by calling boxed(). Here, we will move a primitive IntStream into a Stream&lt;Integer&gt;:

```java
@Test
public void intStream_mapToObjectStream() {
    IntStream intStream = IntStream.of(1, 1, 3, 3, 4);
    Stream&lt;Integer&gt; boxed = intStream.boxed();

    Optional&lt;Integer&gt; mathResult = boxed.reduce((first, second) -&gt; first &#43; 2 * second);

    assertEquals(1 &#43; 2 &#43; 6 &#43; 6 &#43; 8, mathResult.orElseThrow(RuntimeException::new).intValue());
}

```
