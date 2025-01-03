---
title: "The Java Stream API: An Introduction to Collecting Results"
date: 2018-10-21T15:46:38
draft: false
tags: [java, java stream api]
---

You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

Calling `collect(..)` on a stream terminates a stream into a collection. We've already seen that calling collect(Collectors.toList()) moves your stream into
a List<T>, but you can also collect into a set. If we take our familiar collection of names in a String collection:

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

We can make a set out of them like so:

```java
@Test
public void collect_toSet() {
    Set<String> allJNames = names.stream().filter(name -> name.startsWith("J")).collect(Collectors.toSet());

    assertTrue(allJNames.contains("John"));
    assertTrue(allJNames.contains("Jacob"));
}

```

You can join a Stream without using a delimiter:

```java
@Test
public void collect_joining() {
    String allNamesJoined = names.stream().collect(Collectors.joining());

    assertTrue(allNamesJoined.startsWith("JohnJacobJerry"));
}

```

Or you can include a delimiter:

```java
@Test
public void collect_joinWithDelimiter() {
    String commaDelimitedNames = names.stream().collect(Collectors.joining(","));

    assertTrue(commaDelimitedNames.startsWith("John,Jacob,Jerry"));
}

```

Let's move into a slightly more involved example. In a POJO class like so:

```java
public class SimplePair {

    private String name;
    private int id;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getId() {
        return id;
    }

    public void setId(int id) {
        this.id = id;
    }

    @Override
    public String toString() {
        return "name-" + name + ",id-" + id;
    }
}

```

And where we create pairs that have `(id: 1, name: pair1), (id: 2, name: pair2)`....

```java
public static List<SimplePair> generateSimplePairs(int numToGenerate) {
    List<SimplePair> pairs = new ArrayList<>();
    for (int i = 1; i <= numToGenerate; i++) {
        SimplePair pair = new SimplePair();

        pair.setId(i);
        pair.setName("pair" + i);

        pairs.add(pair);
    }
    return pairs;
}

```

We can then collect after a call to `map(..)`, as map continues along the stream:

```java
@Test
public void collect_mapToString() {
    List<SimplePair> twoPairs = TestUtils.generateSimplePairs(2);

    String semiColonDelimited = twoPairs.stream().map(Objects::toString).collect(Collectors.joining(";"));

    assertEquals("name-pair1,id-1;name-pair2,id-2", semiColonDelimited);
}

```

Finally, we can collect a summary of statistics about certain primitive types. If we wanted statistics about the ids of the collection, we could get them with
a call to `collect(Collectors.summarizingInt(SimplePair::getId))`:

```java
@Test
public void collectStatistics() {
    IntSummaryStatistics statistics = simplePairs.stream().collect(Collectors.summarizingInt(SimplePair::getId));

    assertEquals(5, statistics.getCount());
    assertEquals(5, statistics.getMax());
    assertEquals(1, statistics.getMin());
    assertEquals(15, statistics.getSum());
}

```
