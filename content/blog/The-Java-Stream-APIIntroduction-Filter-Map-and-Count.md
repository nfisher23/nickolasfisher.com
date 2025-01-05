---
title: "The Java Stream API--Introduction: Filter, Map, and Count"
date: 2018-10-20T12:00:18
draft: false
tags: [java, java stream api]
---

The sample code provided with this series on the Java Stream API can be retrieved [on GitHub](https://github.com/nfisher23/java_stream_api_samples/tree/master).

The Java Stream API, introduced in Java 8, provides a remarkably simple, yet powerful, interface for manipulating data. In essence, it marries
some of the object oriented features baked into Java with many of the strengths of functional programming. All of that is included with efficient streaming of data--that is,
it is only acted upon when the stream completes.

We'll get started by manipulating a simple collection of names. You can create a stream from a collection by calling `stream()` on a Collection.
This creates a _new_ stream of data from the collection, which does not affect or change the original collection from which the stream is derived.
If we have a collection of names as Strings like so:

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

Then we can see that the original list is not affected by any operations:

```java
@Test
public void originalListUnchanged() {
    List<String> emptyList = names.stream().filter(name -> false).collect(Collectors.toList());

    assertTrue(emptyList.isEmpty());
    assertFalse(names.isEmpty());
    assertEquals("John", names.get(0));
}

```

We can make a collection smaller by calling the filter(..) method, shown initially above, which takes a Predicate<T>.
Anything evaluating to true will be kept in the collection, and anything evaluating to false will be removed. Above, any returned collection
which uses this predicate will return as empty, since our filtering method always returns false.

We can get all the names beginning with "J" with `.filter(name -> name.startsWith("J"))`, and we can collect it into a List that we can work with by calling `collect(Collectors.ToList())`.
The `collect(..)` method is a _terminal operation_, which means that we are done with the stream once we call it, and we can't do anything else with that stream from that point on:

```java
@Test
public void filterByFirstLetter() {
    Stream<String> streamFilteredByFirstLetter = names.stream()
            .filter(name -> name.startsWith("J"));

    List<String> listFilteredByFirstLetter = streamFilteredByFirstLetter.collect(Collectors.toList());

    assertEquals(5, listFilteredByFirstLetter.size());
    assertEquals("John", listFilteredByFirstLetter.get(0));
    assertEquals("Janine", listFilteredByFirstLetter.get(4));
}
```

We can get all names starting with "Jo" in the same way:

```java
@Test
public void filterByFirstTwoLetters() {
    Stream<String> streamFilteredByFirstTwoLetters = names.stream()
            .filter(name -> name.startsWith("Jo"));

    List<String> listFiltered = streamFilteredByFirstTwoLetters.collect(Collectors.toList());

    assertEquals(2, listFiltered.size());
}

```

Another simple terminal operation is `count()`, which, as you can probably guess, counts the number of elements in the stream:

```java
@Test
public void countFilteredValues() {
    long countFilteredByFirstLetter = names.stream().filter(name -> name.startsWith("J")).count();

    assertEquals(5, countFilteredByFirstLetter);
}

```

For large collections, we can even do it in parallel:

```java
@Test
public void parallelCount() {
    long parallelCount = names.parallelStream().filter(name -> name.startsWith("J")).count();

    assertEquals(5, parallelCount);
}

```

When it comes to parallel streams, a good rule of thumb is to make sure that whatever you're doing doesn't manipulate a shared state. I will cover parallel streams in detail in a [different post](https://nickolasfisher.com/blog/the-java-stream-api-parallel-streams).

Finally, a often used method on streams is the `map(..)` method. `map(..)` allows you to take an object and manipulate it for downstream usage. Here, we will add the string " Smith" to every name, so our collection
will look like "John Smith", "Jacob Smith", "Jerry Smith", etc:

```java
@Test
public void addLastName() {
    List<String> theSmiths = names.stream().map(name -> name + " Smith").collect(Collectors.toList());

    assertEquals("John Smith", theSmiths.get(0));
    assertEquals("Jacob Smith", theSmiths.get(1));

    for (String nameWithSmithAsLastName : theSmiths) {
        String lastName = nameWithSmithAsLastName.split(" ")[1];
        assertEquals("Smith", lastName);
    }
}

```

Or we could take the first letter from each name like so:

```java
@Test
public void getFirstLetter() {
    List<String> firstLetters = names.stream().map(name -> name.substring(0, 1)).collect(Collectors.toList());

    assertEquals("J",firstLetters.get(0));
    assertEquals("J",firstLetters.get(1));
    assertEquals("J",firstLetters.get(2));
    assertEquals("A",firstLetters.get(5));
}

```
