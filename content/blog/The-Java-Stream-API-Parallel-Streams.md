---
title: "The Java Stream API: Parallel Streams"
date: 2018-10-01T00:00:00
draft: false
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

Parallel Streams are simple to generate in Java. Instead of calling .stream(), you simply call parallelStream(). Here, we&#39;ll take our familiar list of names:

``` java
public static List&lt;String&gt; getListOfNames() {
    List&lt;String&gt; names = new ArrayList&lt;&gt;();

    names.add(&#34;John&#34;);
    names.add(&#34;Jacob&#34;);
    names.add(&#34;Jerry&#34;);
    names.add(&#34;Josephine&#34;);
    names.add(&#34;Janine&#34;);
    names.add(&#34;Alan&#34;);
    names.add(&#34;Beverly&#34;);

    return names;
}

```

And count them in parallel:

``` java
@Test
public void countingInParallel() {
    long parallelCount = names.parallelStream().filter(name -&gt; name.startsWith(&#34;J&#34;)).count();
    assertEquals(5, parallelCount);
}

```

Parallel Streams are best used for lots of data, but the same gotchas that exist in all concurrent programming still apply. For example,
using our [Fibonacci Stream generator](https://nickolasfisher.com/blog/The-Java-Stream-API-Generating-Fibonacci-Numbers), if we find the first
Fibonacci number over 5000 in a synchronous manner, we can always find the same number later:

``` java
@Test
public void fibonacci_predictableWhenSynchronous() {
    Stream&lt;Integer&gt; fibonaccis_1 = Stream.generate(new SupplyFibonacci());

    Integer firstFibOver5K = fibonaccis_1.peek(System.out::println)
            .filter(num -&gt; num &gt;= 500000).findFirst().orElseThrow(RuntimeException::new);

    Stream&lt;Integer&gt; fibonaccis_2 = Stream.generate(new SupplyFibonacci());

    Integer stillFirstFibOver5K = fibonaccis_2
            .filter(num -&gt; num.intValue() == firstFibOver5K)
            .findFirst().orElseThrow(RuntimeException::new);

    assertEquals(firstFibOver5K, stillFirstFibOver5K);
}

```

However, if we try to do the same thing in parallel, since the Fibonacci Supplier shares state, the chance of getting something deterministic isn&#39;t possible. This test passes and fails unpredictably because it manipulates the shared state (in this case of parallel, we likely wouldn&#39;t be computing Fibonacci numbers at all):

``` java
@Test
public void badUseOfParallel_thisIsUnpredictable() {
    Stream&lt;Integer&gt; fibonaccis_1 = Stream.generate(new SupplyFibonacci());

    Integer firstFibOver5K = fibonaccis_1
            .parallel()
            .peek(System.out::println)
            .filter(num -&gt; num &gt;= 500000)
            .findAny()
            .orElseThrow(RuntimeException::new);

    Stream&lt;Integer&gt; fibonaccis_2 = Stream.generate(new SupplyFibonacci());

    Integer stillFirstFibOver5K = fibonaccis_2
            .parallel()
            .peek(System.out::println)
            .filter(num -&gt; num &gt;= 500000)
            .findAny()
            .orElseThrow(RuntimeException::new);

    assertEquals(firstFibOver5K, stillFirstFibOver5K);
}

```

However, one \*cheap\* lunch is that large collections will be auto-magically broken down into smaller collections and operated on in parallel. If we have, for example,
a list of numbers from 0 to (whatever):

``` java
public List&lt;Integer&gt; generateLargeList(int max) {
    List&lt;Integer&gt; ints = new ArrayList&lt;&gt;();
    for (int i = 0; i &lt; max; i&#43;&#43;) {
        ints.add(i);
    }
    return ints;
}

```

We could then filter them in parallel, and the parallel streams will retain the ordering after we are done:

``` java
@Test
public void parallelStreams_orderedCollectionsRemainOrdered() {
    List&lt;Integer&gt; largeSequentialList = generateLargeList(100000);

    List&lt;Integer&gt; collectedInOrder = largeSequentialList.parallelStream()
            .filter(num -&gt; num &gt;= 1000)
            .peek(System.out::println)
            .collect(Collectors.toList());

    // verify order
    for (int i = 1; i &lt; collectedInOrder.size(); i&#43;&#43;) {
        assertTrue(collectedInOrder.get(i) &gt; collectedInOrder.get(i - 1));
    }
}

```

Finally, there are a number of collectors that work concurrently. If you want to collect into a map concurrently, you do so with
.groupingByConcurrent(..):

``` java
@Test
public void parallelStreams_concurrentMaps() {
    ConcurrentMap&lt;Integer, List&lt;String&gt;&gt; mapToNamesInParallel =
            names.parallelStream()
                    .collect(Collectors.groupingByConcurrent(String::length));

    assertTrue(mapToNamesInParallel.get(4).contains(&#34;Alan&#34;));
    assertTrue(mapToNamesInParallel.get(4).contains(&#34;John&#34;));

    ConcurrentMap&lt;Integer, Long&gt; mapOfCountsInParallel = names.parallelStream()
            .collect(Collectors.groupingByConcurrent(String::length, Collectors.counting()));

    assertEquals(2, mapOfCountsInParallel.get(4).intValue());
}

```


