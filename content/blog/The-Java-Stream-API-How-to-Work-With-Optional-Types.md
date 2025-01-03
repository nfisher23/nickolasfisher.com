---
title: "The Java Stream API: How to Work With Optional Types"
date: 2018-10-20T21:59:38
draft: false
tags: [java, java stream api]
---

You can find the sample code associated with this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

If Java programmers had a generic Facebook page, they would collectively have an "it's complicated" relationship with the null value.

Constantly having to check for null values can certainly be a real boon, both in the readability of your code as well as in the hidden implication that not
checking for null means something might blow up. Of course, you could enforce contracts that say to never return null, but there are unfortunately, valid use cases for null.
For example, if you query for an Account using a primary key and there is no account in the database, letting the method responsible for that
return an empty Account value would be disingenuous--it's not that the Account had empty fields, after all, but that there wasn't an Account at all.

The Java Stream API has provided a thoughtful solution to this problem through its Optional<T> type. The Optional<T> types allows us to more easily
specify behavior that we want to take place if a value exists or not.

For example, working with our familiar set of names:

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

We can select the last element, sorted by case, with the
max(String::comparingToIgnoreCase) declaration. When we do that, we get an Optional:

```java
Optional<String> maxName = names.stream().max(String::compareToIgnoreCase);

```

Now, if we didn't get a maximum name--which might happen if the collection were empty--the Optional would be empty. But if we did, the Optional would contain a value.
One way to deal with that is with the `OrElse(..)` method, which says "if there is a value in the Optional, give me that value. If there is not a value in the Optional, then give me the value I pass in
to the OrElse method:

```java
@Test
public void optional_max() {
    Optional<String> maxName = names.stream().max(String::compareToIgnoreCase);

    assertEquals("Josephine", maxName.orElse(""));
}

```

Above, we can see that Josephine is the max string, i.e. the one last alphabetically in the collection. But what if there is no value? The behavior is predictable:

```java
@Test
public void optional_orElse() {
    Optional<String> doesntExist = names.stream().filter(name -> name.startsWith("Z")).findAny();

    assertEquals("default", doesntExist.orElse("default"));
}

```

Sometimes, if the Optional<T> is empty, we want to run a method that generates a value for use. We can do that with `OrElseGet(..)`,
which takes a Supplier<T>. Here, we will compute the current time value as a String:

```java
@Test
public void optional_orElseGet() {
    Optional<String> doesntExist = names.stream().filter(name -> name.startsWith("Z")).findAny();

    String stringTime = doesntExist.orElseGet(() -> Instant.now().toString());

    System.out.println(stringTime);
}

```

If we don't get a value in an Optional, we might want to throw a custom exception. Without Optionals, our code would just throw a
NullPointerException, which might be too vague for us to easily find a solution to. We can throw a custom exception with
`OrElseThrow(..)`. Here, we will throw a RuntimeException:

```java
@Test(expected = RuntimeException.class)
public void optional_orElseThrow() {
    Optional<String> doesntExist = names.stream().filter(name -> name.startsWith("Z")).findAny();

    doesntExist.orElseThrow(() -> new RuntimeException("No names starting with 'Z' in the collection"));
}
```

Perhaps the most useful of the methods we can run on an Optional<T> is `ifPresent(..)`. `ifPresent(..)` runs only if the Optional
contains a value, does nothing otherwise, and it takes a Consumer<T>. If we have a real simple Consumer that simply saves the value you
pass into it:

```java
private class SimpleConsumer implements Consumer<String> {
    String internalValue = null;

    @Override
    public void accept(String s) {
        internalValue = s;
    }
}

```

We can then validate that the method does, in fact, run, with a test like so:

```java
@Test
public void optional_ifPresent_exists() {
    Optional<String> alan = names.stream().filter(name -> name.equals("Alan")).findFirst();

    SimpleConsumer shouldRun = new SimpleConsumer();
    alan.ifPresent(shouldRun);

    assertEquals("Alan", shouldRun.internalValue);
}

```

Whereas it does nothing if there isn't a value:

```java
@Test
public void optional_ifPresent_DNE() {
    Optional<String> notHere = names.stream().filter(name -> name.equals("Not a Real Name")).findFirst();

    notHere.ifPresent(name -> { throw new RuntimeException("this exception won't get thrown"); });
}

```

There are other methods we can run on Optionals as well, which have parallel concepts to Streams. In many ways, it's fair to think of
an Optional<T> as a Stream with zero or one elements. We can map the value, if there is one, like so:

```
@Test
public void optional_map() {
    Optional<String> alan = names.stream().filter(name -> name.equals("Alan")).findFirst();

    Optional<String> firstChar = alan.map(name -> name.substring(0, 1));

    assertEquals("A", firstChar.orElseThrow(RuntimeException::new));
}

```
