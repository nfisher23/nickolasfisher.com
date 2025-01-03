---
title: "The Java Stream API: Creating Custom, Lazy, Infinite Streams"
date: 2018-10-20T13:50:54
draft: false
tags: [java, java stream api]
---

You can find the sample code from this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

There are a few built in ways to create your own custom streams. While many collections offer a direct `.stream()` method,
you can also use `Stream.of(..)` to just make one in place:

```java
@Test
public void simpleStream() {
    Stream<String> emotions = Stream.of("happy", "sad", "ecstatic", "joyful", "exuberant", "jealous");

    List<String> listOfJs = emotions.filter(emotion -> emotion.startsWith("j")).collect(Collectors.toList());

    assertEquals(2, listOfJs.size());
}

```

Streams in Java are lazy by default. This means that nothing actually happens, and data doesn't actually start flowing, until we ask for it
via terminal operations. For example, if we have our familiar collection of names:

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

And we run:

```java
@Test
public void lazyStreams() {
    // nothing gets printed
    Stream<String> template = names.stream().peek(System.out::println).filter(n -> n.length() > 4);
}

```

Nothing gets printed to the console, because the stream has not been terminated, and no data is flowing. For all intensive purposes, nothing tangible has happened (e.g. a meeting at work).

To get the `println()` method to execute, you would have to call a terminal operator:

```
@Test
public void lazyStreams_withTerminalOperator() {
    Stream<String> template = names.stream().peek(System.out::println).filter(n -> n.length() > 4);

    // execute here
    template.collect(Collectors.toList());
}

```

This concept presents a lot of interesting opportunities. The most obvious that might come to mind would be the idea of infinite streams.
Because nothing gets executed, we can create a template that acts as an "infinite" stream. One way to do this is via the `Stream.generate(..)`
method, which takes a Supplier. We can create a count from zero to infinity like so:

```java
private class SupplyInfinity implements Supplier<Integer> {
    private int counter = 0;

    @Override
    public Integer get() {
        return counter++;
    }

}

@Test
public void infinteStreams_withCustomSupplier() {
    Stream<Integer> infinity = Stream.generate(new SupplyInfinity());

    List<Integer> collected = infinity.limit(100).collect(Collectors.toList());

    assertEquals(99, collected.get(99).intValue());
}

```

Calling `limit(..)`, predictably, limits the number of elements in the stream. So here, we generate the numbers 0 to 99.

Streams are lazy, which means that a data point is pulled from the beginning of the stream and drawn through the stream only when it has to.
This means that infinite streams still get processed one element at a time. For example:

```java
@Test
public void verifyLazinessOfStream() {
    Stream.iterate(0.0, num -> num + (new Random()).nextInt(2) - .5)
            .peek(num -> System.out.println("getting " + num))
            .limit(5).collect(Collectors.toList());
}

```

This prints out one hundred random elements, even though we're calling `peek(..)` before we tell the stream to limit the results to five.

We can also create an infinite stream using the `Stream.iterate(..)` method. Here, you pass in a seed value, then a method to act on each subsequent value, which gets computed from the
previous value. So, if we want to get the numbers 0 to 99, we would start the iterator with zero and add one to it each time:

```java
@Test
public void infiniteStreams_withIterate() {
    Stream<Integer> infinity = Stream.iterate(0, num -> num + 1);

    List<Integer> collected = infinity.limit(100).collect(Collectors.toList());

    assertEquals(99, collected.get(99).intValue());
}

```
