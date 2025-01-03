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

We&#39;ll get started by manipulating a simple collection of names. You can create a stream from a collection by calling `stream()` on a Collection.
This creates a _new_ stream of data from the collection, which does not affect or change the original collection from which the stream is derived.
If we have a collection of names as Strings like so:

```java
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

Then we can see that the original list is not affected by any operations:

```java
@Test
public void originalListUnchanged() {
    List&lt;String&gt; emptyList = names.stream().filter(name -&gt; false).collect(Collectors.toList());

    assertTrue(emptyList.isEmpty());
    assertFalse(names.isEmpty());
    assertEquals(&#34;John&#34;, names.get(0));
}

```

We can make a collection smaller by calling the filter(..) method, shown initially above, which takes a Predicate&lt;T&gt;.
Anything evaluating to true will be kept in the collection, and anything evaluating to false will be removed. Above, any returned collection
which uses this predicate will return as empty, since our filtering method always returns false.

We can get all the names beginning with &#34;J&#34; with `.filter(name -&gt; name.startsWith(&#34;J&#34;))`, and we can collect it into a List that we can work with by calling `collect(Collectors.ToList())`.
The `collect(..)` method is a _terminal operation_, which means that we are done with the stream once we call it, and we can&#39;t do anything else with that stream from that point on:

```java
@Test
public void filterByFirstLetter() {
    Stream&lt;String&gt; streamFilteredByFirstLetter = names.stream()
            .filter(name -&gt; name.startsWith(&#34;J&#34;));

    List&lt;String&gt; listFilteredByFirstLetter = streamFilteredByFirstLetter.collect(Collectors.toList());

    assertEquals(5, listFilteredByFirstLetter.size());
    assertEquals(&#34;John&#34;, listFilteredByFirstLetter.get(0));
    assertEquals(&#34;Janine&#34;, listFilteredByFirstLetter.get(4));
}
```

We can get all names starting with &#34;Jo&#34; in the same way:

```java
@Test
public void filterByFirstTwoLetters() {
    Stream&lt;String&gt; streamFilteredByFirstTwoLetters = names.stream()
            .filter(name -&gt; name.startsWith(&#34;Jo&#34;));

    List&lt;String&gt; listFiltered = streamFilteredByFirstTwoLetters.collect(Collectors.toList());

    assertEquals(2, listFiltered.size());
}

```

Another simple terminal operation is `count()`, which, as you can probably guess, counts the number of elements in the stream:

```java
@Test
public void countFilteredValues() {
    long countFilteredByFirstLetter = names.stream().filter(name -&gt; name.startsWith(&#34;J&#34;)).count();

    assertEquals(5, countFilteredByFirstLetter);
}

```

For large collections, we can even do it in parallel:

```java
@Test
public void parallelCount() {
    long parallelCount = names.parallelStream().filter(name -&gt; name.startsWith(&#34;J&#34;)).count();

    assertEquals(5, parallelCount);
}

```

When it comes to parallel streams, a good rule of thumb is to make sure that whatever you&#39;re doing doesn&#39;t manipulate a shared state. I will cover parallel streams in detail in a [different post](https://nickolasfisher.com/blog/The-Java-Stream-API-Parallel-Streams).

Finally, a often used method on streams is the `map(..)` method. `map(..)` allows you to take an object and manipulate it for downstream usage. Here, we will add the string &#34; Smith&#34; to every name, so our collection
will look like &#34;John Smith&#34;, &#34;Jacob Smith&#34;, &#34;Jerry Smith&#34;, etc:

```java
@Test
public void addLastName() {
    List&lt;String&gt; theSmiths = names.stream().map(name -&gt; name &#43; &#34; Smith&#34;).collect(Collectors.toList());

    assertEquals(&#34;John Smith&#34;, theSmiths.get(0));
    assertEquals(&#34;Jacob Smith&#34;, theSmiths.get(1));

    for (String nameWithSmithAsLastName : theSmiths) {
        String lastName = nameWithSmithAsLastName.split(&#34; &#34;)[1];
        assertEquals(&#34;Smith&#34;, lastName);
    }
}

```

Or we could take the first letter from each name like so:

```java
@Test
public void getFirstLetter() {
    List&lt;String&gt; firstLetters = names.stream().map(name -&gt; name.substring(0, 1)).collect(Collectors.toList());

    assertEquals(&#34;J&#34;,firstLetters.get(0));
    assertEquals(&#34;J&#34;,firstLetters.get(1));
    assertEquals(&#34;J&#34;,firstLetters.get(2));
    assertEquals(&#34;A&#34;,firstLetters.get(5));
}

```
