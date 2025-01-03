---
title: "The Java Stream API: Concatenating, Sorting, and Flat-Mapping"
date: 2018-10-20T21:32:57
draft: false
---

The sample code associated with this post can be found [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

Sometimes, we will have two different streams of data that we want to aggregate into one stream to analyze. In that case, we can use the `Stream.concat(..)` method. Here, if we take our list of names from before:

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

We can concatenate those names that start with &#34;Jo&#34; with those names that start with &#34;Ja&#34;:

```java
@Test
public void concatenating() {
    Stream&lt;String&gt; startsWithJo = names.stream().filter(name -&gt; name.startsWith(&#34;Jo&#34;));
    Stream&lt;String&gt; startsWithJa = names.stream().filter(name -&gt; name.startsWith(&#34;Ja&#34;));

    List&lt;String&gt; combined = Stream.concat(startsWithJo, startsWithJa).collect(Collectors.toList());

    assertEquals(&#34;John&#34;, combined.get(0));
    assertEquals(&#34;Jacob&#34;, combined.get(2));
```

In such situations, it&#39;s not uncommon to want to find those values which are distinct--i.e. different from other values in the stream. We can do that with the distinct(..) method:

```java
@Test
public void distinct() {
    String jolene = &#34;Jolene&#34;;
    names.add(jolene);
    names.add(jolene);
    names.add(jolene);

    List&lt;String&gt; jolenes = names.stream().filter(name -&gt; name.equals(jolene)).collect(Collectors.toList());

    assertEquals(3, jolenes.size());

    List&lt;String&gt; distinctJolene = jolenes.stream().distinct().collect(Collectors.toList());

    assertEquals(1, distinctJolene.size());
}

```

You can sort a stream&#39;s elements using the `.sorted(..)` method, which takes a Comparator&lt;T&gt;. Here, we&#39;ll sort the stream&#39;s elements by the first letter in each name:

```java
@Test
public void sorting() {
    Stream&lt;String&gt; sortedByFirstLetter = names.stream().sorted(new Comparator&lt;String&gt;() {
        @Override
        public int compare(String first, String second) {
            // by first letter
            if (first.charAt(0) &gt; second.charAt(0)) {
                return 1;
            } else if (first.charAt(0) &lt; second.charAt(0)) {
                return -1;
            }
            return 0;
        }
    });

    List&lt;String&gt; sortedAsList = sortedByFirstLetter.collect(Collectors.toList());

    assertEquals(&#34;Alan&#34;, sortedAsList.get(0));
    assertEquals(&#34;Beverly&#34;, sortedAsList.get(1));
}

```

You can _flat map_ a stream of a stream. Flat mapping is weird to think about at first, but basically it applies a mapping function to each of the streams within a stream. Say we have a stream-generating
function that takes a word and returns a Stream of letters as Strings:

```java
private Stream&lt;String&gt; getCharactersAsStream(String word) {
    List&lt;String&gt; chars = new ArrayList&lt;&gt;();
    for (int i = 0; i &lt; word.length(); i&#43;&#43;) {
        chars.add(word.substring(i, i &#43; 1));
    }
    return chars.stream();
}
```

Now, calling this method on a stream of names would yield a stream that, if collected, would look like \[\[&#34;j&#34;,&#34;o&#34;,&#34;h&#34;,&#34;n&#34;\],\[&#34;j&#34;,&#34;a&#34;,&#34;c&#34;,&#34;o&#34;,&#34;b&#34;\]...\]. This could be difficult to work with, so let&#39;s say we want to map
that collection that removes the inner collections, leaving us with \[&#34;j&#34;,&#34;o&#34;,&#34;h&#34;,&#34;n&#34;,&#34;j&#34;,&#34;a&#34;,&#34;c&#34;,&#34;o&#34;,&#34;b&#34;,...\]. Well, flat map is how you do it:

```java
@Test
public void flatMapping() {
    Stream&lt;Stream&lt;String&gt;&gt; streamsOnStreams = names.stream().map(name -&gt; getCharactersAsStream(name));

    List&lt;Stream&lt;String&gt;&gt; collected = streamsOnStreams.collect(Collectors.toList());
    String[] charsOfJohn = collected.get(0).collect(Collectors.toList()).toArray(new String[0]);
    String[] charsOfJacob = collected.get(1).collect(Collectors.toList()).toArray(new String[0]);

    assertTrue(Arrays.equals(new String[] {&#34;J&#34;, &#34;o&#34;,&#34;h&#34;,&#34;n&#34;}, charsOfJohn));
    assertTrue(Arrays.equals(new String[] {&#34;J&#34;, &#34;a&#34;,&#34;c&#34;,&#34;o&#34;, &#34;b&#34;}, charsOfJacob));

    List&lt;String&gt; allCharactersFlatMapped = names.stream().flatMap(name -&gt; getCharactersAsStream(name)).collect(Collectors.toList());

    assertEquals(&#34;J&#34;, allCharactersFlatMapped.get(0));
    assertEquals(&#34;o&#34;, allCharactersFlatMapped.get(1));
    assertEquals(&#34;h&#34;, allCharactersFlatMapped.get(2));
    assertEquals(&#34;n&#34;, allCharactersFlatMapped.get(3));
    assertEquals(&#34;J&#34;, allCharactersFlatMapped.get(4));
    assertEquals(&#34;a&#34;, allCharactersFlatMapped.get(5));
    assertEquals(&#34;c&#34;, allCharactersFlatMapped.get(6));
    assertEquals(&#34;o&#34;, allCharactersFlatMapped.get(7));
    assertEquals(&#34;b&#34;, allCharactersFlatMapped.get(8));
}

```
