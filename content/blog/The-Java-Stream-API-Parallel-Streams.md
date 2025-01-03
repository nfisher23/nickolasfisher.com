---
title: "The Java Stream API: Parallel Streams"
date: 2018-10-21T20:03:56
draft: false
tags: [java, java stream api]
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

Parallel Streams are simple to generate in Java. Instead of calling .stream(), you simply call parallelStream(). Here, we'll take our familiar list of names:

```java
public static List<String> getListOfNames() {
    List<String> names = new ArrayList<>();

    names.add("John");
    names.add("Jacob");
    names.add("Jerry");
    names.add("Josephine");
    names.add("Janine");
    names.add("Alan");
    names.add("Beverly");

    return names;
}

```

And count them in parallel:

```java
@Test
public void countingInParallel() {
    long parallelCount = names.parallelStream().filter(name -> name.startsWith("J")).count();
    assertEquals(5, parallelCount);
}

```

Parallel Streams are best used for lots of data, but the same gotchas that exist in all concurrent programming still apply. For example,
using our [Fibonacci Stream generator](https://nickolasfisher.com/blog/The-Java-Stream-API-Generating-Fibonacci-Numbers), if we find the first
Fibonacci number over 5000 in a synchronous manner, we can always find the same number later:

```java
@Test
public void fibonacci_predictableWhenSynchronous() {
    Stream<Integer> fibonaccis_1 = Stream.generate(new SupplyFibonacci());

    Integer firstFibOver5K = fibonaccis_1.peek(System.out::println)
            .filter(num -> num >= 500000).findFirst().orElseThrow(RuntimeException::new);

    Stream<Integer> fibonaccis_2 = Stream.generate(new SupplyFibonacci());

    Integer stillFirstFibOver5K = fibonaccis_2
            .filter(num -> num.intValue() == firstFibOver5K)
            .findFirst().orElseThrow(RuntimeException::new);

    assertEquals(firstFibOver5K, stillFirstFibOver5K);
}

```

However, if we try to do the same thing in parallel, since the Fibonacci Supplier shares state, the chance of getting something deterministic isn't possible. This test passes and fails unpredictably because it manipulates the shared state (in this case of parallel, we likely wouldn't be computing Fibonacci numbers at all):

```java
@Test
public void badUseOfParallel_thisIsUnpredictable() {
    Stream<Integer> fibonaccis_1 = Stream.generate(new SupplyFibonacci());

    Integer firstFibOver5K = fibonaccis_1
            .parallel()
            .peek(System.out::println)
            .filter(num -> num >= 500000)
            .findAny()
            .orElseThrow(RuntimeException::new);

    Stream<Integer> fibonaccis_2 = Stream.generate(new SupplyFibonacci());

    Integer stillFirstFibOver5K = fibonaccis_2
            .parallel()
            .peek(System.out::println)
            .filter(num -> num >= 500000)
            .findAny()
            .orElseThrow(RuntimeException::new);

    assertEquals(firstFibOver5K, stillFirstFibOver5K);
}

```

However, one \*cheap\* lunch is that large collections will be auto-magically broken down into smaller collections and operated on in parallel. If we have, for example,
a list of numbers from 0 to (whatever):

```java
public List<Integer> generateLargeList(int max) {
    List<Integer> ints = new ArrayList<>();
    for (int i = 0; i < max; i++) {
        ints.add(i);
    }
    return ints;
}

```

We could then filter them in parallel, and the parallel streams will retain the ordering after we are done:

```java
@Test
public void parallelStreams_orderedCollectionsRemainOrdered() {
    List<Integer> largeSequentialList = generateLargeList(100000);

    List<Integer> collectedInOrder = largeSequentialList.parallelStream()
            .filter(num -> num >= 1000)
            .peek(System.out::println)
            .collect(Collectors.toList());

    // verify order
    for (int i = 1; i < collectedInOrder.size(); i++) {
        assertTrue(collectedInOrder.get(i) > collectedInOrder.get(i - 1));
    }
}

```

Finally, there are a number of collectors that work concurrently. If you want to collect into a map concurrently, you do so with
.groupingByConcurrent(..):

```java
@Test
public void parallelStreams_concurrentMaps() {
    ConcurrentMap<Integer, List<String>> mapToNamesInParallel =
            names.parallelStream()
                    .collect(Collectors.groupingByConcurrent(String::length));

    assertTrue(mapToNamesInParallel.get(4).contains("Alan"));
    assertTrue(mapToNamesInParallel.get(4).contains("John"));

    ConcurrentMap<Integer, Long> mapOfCountsInParallel = names.parallelStream()
            .collect(Collectors.groupingByConcurrent(String::length, Collectors.counting()));

    assertEquals(2, mapOfCountsInParallel.get(4).intValue());
}

```
