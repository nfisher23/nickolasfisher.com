---
title: "The Java Stream API: An Introduction to Collecting Results"
date: 2018-10-21T15:46:38
draft: false
tags: [java, java stream api]
---

You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

Calling `collect(..)` on a stream terminates a stream into a collection. We&#39;ve already seen that calling collect(Collectors.toList()) moves your stream into
a List&lt;T&gt;, but you can also collect into a set. If we take our familiar collection of names in a String collection:

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

We can make a set out of them like so:

```java
@Test
public void collect_toSet() {
    Set&lt;String&gt; allJNames = names.stream().filter(name -&gt; name.startsWith(&#34;J&#34;)).collect(Collectors.toSet());

    assertTrue(allJNames.contains(&#34;John&#34;));
    assertTrue(allJNames.contains(&#34;Jacob&#34;));
}

```

You can join a Stream without using a delimiter:

```java
@Test
public void collect_joining() {
    String allNamesJoined = names.stream().collect(Collectors.joining());

    assertTrue(allNamesJoined.startsWith(&#34;JohnJacobJerry&#34;));
}

```

Or you can include a delimiter:

```java
@Test
public void collect_joinWithDelimiter() {
    String commaDelimitedNames = names.stream().collect(Collectors.joining(&#34;,&#34;));

    assertTrue(commaDelimitedNames.startsWith(&#34;John,Jacob,Jerry&#34;));
}

```

Let&#39;s move into a slightly more involved example. In a POJO class like so:

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
        return &#34;name-&#34; &#43; name &#43; &#34;,id-&#34; &#43; id;
    }
}

```

And where we create pairs that have `(id: 1, name: pair1), (id: 2, name: pair2)`....

```java
public static List&lt;SimplePair&gt; generateSimplePairs(int numToGenerate) {
    List&lt;SimplePair&gt; pairs = new ArrayList&lt;&gt;();
    for (int i = 1; i &lt;= numToGenerate; i&#43;&#43;) {
        SimplePair pair = new SimplePair();

        pair.setId(i);
        pair.setName(&#34;pair&#34; &#43; i);

        pairs.add(pair);
    }
    return pairs;
}

```

We can then collect after a call to `map(..)`, as map continues along the stream:

```java
@Test
public void collect_mapToString() {
    List&lt;SimplePair&gt; twoPairs = TestUtils.generateSimplePairs(2);

    String semiColonDelimited = twoPairs.stream().map(Objects::toString).collect(Collectors.joining(&#34;;&#34;));

    assertEquals(&#34;name-pair1,id-1;name-pair2,id-2&#34;, semiColonDelimited);
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
