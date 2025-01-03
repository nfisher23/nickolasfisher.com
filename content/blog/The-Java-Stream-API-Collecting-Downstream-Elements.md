---
title: "The Java Stream API: Collecting Downstream Elements"
date: 2018-10-21T16:29:32
draft: false
tags: [java, java stream api]
---

You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

One interesting feature of collecting streams using the `Collectors.groupingBy(..)` method is the ability to manipulate _downstream_ elements. Basically,
this means that, after you group the keys of the map, you can further make changes to the collection that the map is pointing to. By default, it collects to a list.

We'll start with a SimplePair object:

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

Then, if we generate a collection of SimplePairs:

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

And we add duplicate ids for the third element like:

```java
private void addDuplicatePairs() {
    simplePairs.add(new SimplePair() {{
        setId(3);
        setName("another-pair3");
    }});

    simplePairs.add(new SimplePair() {{
        setId(3);
        setName("yet-another-pair3");
    }});
}

```

Now our collection looks like "\[(id: 1, name: pair1), (id: 2, name: pair2), (id: 3, name: pair3), (id: 3, name: another-pair3), (id: 3, name: yet-another-pair3) ... \]"

Now that we have data to work with, we can get to manipulating the downstream elements, we can map based on the id to a List<SimplePair>, which is the default of groupingBy(..), like:

```java
@Test
public void groupingBy_toList() {
    addDuplicatePairs();

    Map<Integer, List<SimplePair>> defaultsToList = simplePairs.stream().collect(
            Collectors.groupingBy(SimplePair::getId)
    );

    assertEquals(3, defaultsToList.get(3).size());
}

```

You can insist that it collects into a set by passing in `Collectors.toSet(..)` downstream:

```java
@Test
public void groupingBy_toSet() {
    addDuplicatePairs();

    Map<Integer, Set<SimplePair>> idToSetOfPairs = simplePairs.stream().collect(
            Collectors.groupingBy(SimplePair::getId, Collectors.toSet())
    );

    assertEquals(3, idToSetOfPairs.get(3).size());
}

```

You can count the number of elements in the collection downstream, and map to that, by calling `Collectors.counting()` on the downstream elements:

```java
@Test
public void groupingBy_count() {
    addDuplicatePairs();

    Map<Integer, Long> countIdOccurrence = simplePairs.stream().collect(
            Collectors.groupingBy(SimplePair::getId, Collectors.counting())
    );

    assertEquals(3, countIdOccurrence.get(3).intValue());
    assertEquals(1, countIdOccurrence.get(1).intValue());
}

```

You can sum all of the values of a specific property downstream by calling `Collectors.summingInt(Class::property)`.
Here, we sum up all the id's for the downstream elements:

```java
@Test
public void groupingBy_sumDownstreamElements() {
    addDuplicatePairs();

    Map<Integer, Integer> addUpIds = simplePairs.stream().collect(
            Collectors.groupingBy(SimplePair::getId, Collectors.summingInt(SimplePair::getId))
    );

    assertEquals(9, addUpIds.get(3).intValue());
    assertEquals(4, addUpIds.get(4).intValue());
}

```

You can get the maximum length downstream by passing in a Comparator<T> to `Collectors.maxBy(..)` and
specifying the `length()` to be compared:

```java
@Test
public void groupingBy_getMaxDownstreamElement() {
    addDuplicatePairs();

    Map<Integer, Optional<SimplePair>> sortByMaxDownstream = simplePairs.stream().collect(
            Collectors.groupingBy(SimplePair::getId, Collectors.maxBy(
                    Comparator.comparing(sp -> sp.getName().length())
            ))
    );

    String maxNameOfThree = sortByMaxDownstream.get(3).orElseThrow(RuntimeException::new).getName();

    assertEquals("yet-another-pair3", maxNameOfThree);
}

```

You can get the minimum value using the same approach but with the `Collectors.minBy(..)` method:

```java
@Test
public void groupingBy_getMinDownstreamElement() {
    addDuplicatePairs();

    Map<Integer, Optional<SimplePair>> sortByMinDownstream = simplePairs.stream().collect(
            Collectors.groupingBy(SimplePair::getId, Collectors.minBy(
                    Comparator.comparing(simplePair -> simplePair.getName().length())
            ))
    );

    String minNameOfThree = sortByMinDownstream.get(3).orElseThrow(RuntimeException::new).getName();

    assertEquals("pair3", minNameOfThree);
}

```

Finally, you can nest downstream elements as much as you would like. Here, we map the ids to a collection of Integers, which are the length() value
of the name field in SimplePair. This can be a little difficult to wrap your head around at first--basically, we are collecting a Map<\> of ids to objects, then
we are collecting to the List into a Map<>, where the map is a map of the lengths of the name property (say that five times fast):

```java
@Test
public void groupingBy_mapsToMaps() {
    addDuplicatePairs();

    Map<Integer, Map<Integer, List<SimplePair>>> mapToSetOfLengths = simplePairs.stream().collect(Collectors.groupingBy(
            SimplePair::getId,
            Collectors.groupingBy(sp -> sp.getName().length(), Collectors.toList())
    ));

    Map<Integer, List<SimplePair>> lengthsToSimplePairsWithId1 = mapToSetOfLengths.get(1);
    Map<Integer, List<SimplePair>> lengthsToSimplePairsWithId3 = mapToSetOfLengths.get(3);

    assertEquals(1, lengthsToSimplePairsWithId1.size());
    assertEquals(3, lengthsToSimplePairsWithId3.size());
}

```

This process can get pretty confusing, and it's not likely to be helpful in the vast majority of situations. Getting too cute with downstream elements could leave anyone else who looks at the code (including you) with a lot of questions--which takes up valuable time. But, it is one obscure tool to throw in the garage.

For a slightly less obscure example, but still fairly out there, we turn to `Collectors.mapping(..)`, which collects the mapping downstream
into a collection of your choosing. Here, we'll collect a list of length() properties in the downstream SimplePair element:

```java
@Test
public void groupingBy_mappingToMoreDownstreamElements() {
    addDuplicatePairs();

    Map<Integer, List<Integer>> mapIdsToSetOfLengths = simplePairs.stream().collect(Collectors.groupingBy(
            SimplePair::getId,
            Collectors.mapping(sp -> sp.getName().length(), Collectors.toList())
    ));

    assertEquals(5, mapIdsToSetOfLengths.get(3).get(0).intValue());
    assertEquals(13, mapIdsToSetOfLengths.get(3).get(1).intValue());
}

```
