---
title: "The Java Stream API: Concatenating, Sorting, and Flat-Mapping"
date: 2018-10-20T21:32:57
draft: false
tags: [java, java stream api]
---

The sample code associated with this post can be found [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

Sometimes, we will have two different streams of data that we want to aggregate into one stream to analyze. In that case, we can use the `Stream.concat(..)` method. Here, if we take our list of names from before:

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

We can concatenate those names that start with "Jo" with those names that start with "Ja":

```java
@Test
public void concatenating() {
    Stream<String> startsWithJo = names.stream().filter(name -> name.startsWith("Jo"));
    Stream<String> startsWithJa = names.stream().filter(name -> name.startsWith("Ja"));

    List<String> combined = Stream.concat(startsWithJo, startsWithJa).collect(Collectors.toList());

    assertEquals("John", combined.get(0));
    assertEquals("Jacob", combined.get(2));
```

In such situations, it's not uncommon to want to find those values which are distinct--i.e. different from other values in the stream. We can do that with the distinct(..) method:

```java
@Test
public void distinct() {
    String jolene = "Jolene";
    names.add(jolene);
    names.add(jolene);
    names.add(jolene);

    List<String> jolenes = names.stream().filter(name -> name.equals(jolene)).collect(Collectors.toList());

    assertEquals(3, jolenes.size());

    List<String> distinctJolene = jolenes.stream().distinct().collect(Collectors.toList());

    assertEquals(1, distinctJolene.size());
}

```

You can sort a stream's elements using the `.sorted(..)` method, which takes a Comparator<T>. Here, we'll sort the stream's elements by the first letter in each name:

```java
@Test
public void sorting() {
    Stream<String> sortedByFirstLetter = names.stream().sorted(new Comparator<String>() {
        @Override
        public int compare(String first, String second) {
            // by first letter
            if (first.charAt(0) > second.charAt(0)) {
                return 1;
            } else if (first.charAt(0) < second.charAt(0)) {
                return -1;
            }
            return 0;
        }
    });

    List<String> sortedAsList = sortedByFirstLetter.collect(Collectors.toList());

    assertEquals("Alan", sortedAsList.get(0));
    assertEquals("Beverly", sortedAsList.get(1));
}

```

You can _flat map_ a stream of a stream. Flat mapping is weird to think about at first, but basically it applies a mapping function to each of the streams within a stream. Say we have a stream-generating
function that takes a word and returns a Stream of letters as Strings:

```java
private Stream<String> getCharactersAsStream(String word) {
    List<String> chars = new ArrayList<>();
    for (int i = 0; i < word.length(); i++) {
        chars.add(word.substring(i, i + 1));
    }
    return chars.stream();
}
```

Now, calling this method on a stream of names would yield a stream that, if collected, would look like \[\["j","o","h","n"\],\["j","a","c","o","b"\]...\]. This could be difficult to work with, so let's say we want to map
that collection that removes the inner collections, leaving us with \["j","o","h","n","j","a","c","o","b",...\]. Well, flat map is how you do it:

```java
@Test
public void flatMapping() {
    Stream<Stream<String>> streamsOnStreams = names.stream().map(name -> getCharactersAsStream(name));

    List<Stream<String>> collected = streamsOnStreams.collect(Collectors.toList());
    String[] charsOfJohn = collected.get(0).collect(Collectors.toList()).toArray(new String[0]);
    String[] charsOfJacob = collected.get(1).collect(Collectors.toList()).toArray(new String[0]);

    assertTrue(Arrays.equals(new String[] {"J", "o","h","n"}, charsOfJohn));
    assertTrue(Arrays.equals(new String[] {"J", "a","c","o", "b"}, charsOfJacob));

    List<String> allCharactersFlatMapped = names.stream().flatMap(name -> getCharactersAsStream(name)).collect(Collectors.toList());

    assertEquals("J", allCharactersFlatMapped.get(0));
    assertEquals("o", allCharactersFlatMapped.get(1));
    assertEquals("h", allCharactersFlatMapped.get(2));
    assertEquals("n", allCharactersFlatMapped.get(3));
    assertEquals("J", allCharactersFlatMapped.get(4));
    assertEquals("a", allCharactersFlatMapped.get(5));
    assertEquals("c", allCharactersFlatMapped.get(6));
    assertEquals("o", allCharactersFlatMapped.get(7));
    assertEquals("b", allCharactersFlatMapped.get(8));
}

```
