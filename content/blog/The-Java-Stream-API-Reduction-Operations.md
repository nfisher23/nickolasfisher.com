---
title: "The Java Stream API: Reduction Operations"
date: 2018-10-21T19:38:40
draft: false
tags: [java, java stream api]
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

Reduction operations are a way to consolidate collections into one simple result.

Given our SimplePair object:

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

And a collection like:

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

Often, we would want to use this to sum up or multiply members in a particular way. Here, we will
sum all of the ids of our simple pairs (the id's in this collection are 1, 2, 3, 4, and 5):

```java
@Test
public void reduce_sumAllIds() {
    // sums like x_0 + x_1 + ... + x_n:
    Optional<Integer> idsSummed = pairs.stream()
            .map(SimplePair::getId)
            .reduce((firstId, secondId) -> firstId + secondId);

    assertEquals(15, idsSummed.orElseThrow(RuntimeException::new).intValue());
}

```

This above version of the reduce(..) method takes a BinaryOperator<T> object, which gets applied in sequence. In the
above example, the result is a predictable addition of 1 + 2 + 3 + 4 + 5. It takes the resulting sum that has been accumulated
so far and adds it to the next Integer in the sequence. If we wanted to multiply all of the ids together, we can do
so by changing the addition operator to a multiplication operator, like so:

```java
@Test
public void reduce_multiplyAllIds() {
    Optional<Integer> idsMultiplied = pairs.stream()
            .map(SimplePair::getId)
            .reduce((firstId, secondId) -> firstId * secondId);

    assertEquals(1 * 2 * 3 * 4 * 5, idsMultiplied.orElseThrow(RuntimeException::new).intValue());
}

```

Finally, we can seed an initial value in the reduce(..) method. Typically, this would be an identity operator, like zero for addition and one
for multiplication, which allows you to drop the Optional<T> wrapper and just get a value, where the value returned would just be the seed value
if there is no data in the Stream. Here, we will add up all the ids, starting with the number 10:

```java
@Test
public void reduce_usingIdentityValue() {
    Integer idsSummedWithIdentity = pairs.stream()
            .map(SimplePair::getId)
            .reduce(10, (firstId, secondId) -> firstId + secondId);

    assertEquals(25, idsSummedWithIdentity.intValue());
}
```
