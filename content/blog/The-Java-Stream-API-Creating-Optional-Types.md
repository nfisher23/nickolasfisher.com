---
title: "The Java Stream API: Creating Optional Types"
date: 2018-10-21T15:22:54
draft: false
tags: [java, java stream api]
---

You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

While Optionals are often used in conjunction with the Java Stream API, you can also create your own.
Now, why would you want to do that? Simply put, null pointer exceptions are not a fun time, and embracing optional
types will greatly simplify code development, and prevent premature graying hair.

You can create an Optional with `Optional.of(..)`, `Optional.ofNullable(..)`, or `Optional.empty()`. Let's say we want to make a
square root method which will ignore values less than zero. Here's how we might do it:

```java
private Optional<Double> sqrt(Double num) {
    if (num == null) {
        return Optional.ofNullable(num);
    } else if (num >= 0) {
        return Optional.of(Math.sqrt(num));
    } else {
        return Optional.empty();
    }
}

```

We can test this method works in all three of the scenarios we care about--positive number, negative number, null--like so:

```java
@Test
public void optional_createPositive_works() {
    Double positive = 8.8;
    Optional<Double> sqrtPositive = sqrt(positive);

    assertTrue(sqrtPositive.isPresent());
}

@Test
public void optional_createNegative_stillWorks() {
    Double negative = -6.5;
    Optional<Double> sqrtNegative = sqrt(negative);

    assertFalse(sqrtNegative.isPresent());
}

@Test
public void optional_createNull_stillWorks() {
    Optional<Double> optionalNull = sqrt(null);
    assertFalse(optionalNull.isPresent());
}

```

To continue down this path, a really neat feature of Optional types is that you can call a chain of methods on them, and if the
optional goes empty at any point during the chain, it won't blow up. Without optional types, again, a null pointer exception will
blow up your code. Say we wanted to add a logarithm method to our collection of computations:

```java
private Optional<Double> log(Double num) {
    if (num != null &amp;&amp; num > 0) {
        return Optional.of(Math.log(num));
    } else {
        return Optional.empty();
    }
}

```

We could then chain calls together using the `flatMap(..)` method:

```java
@Test
public void optional_getsRealValue() {
    Double positive = 1.0;
    Optional<Double> sqrtPositive = sqrt(positive);
    Optional<Double> realVal = sqrtPositive.flatMap(this::log);

    assertEquals(0, realVal.orElseThrow(RuntimeException::new).intValue());
}

```

However, we can still chain together calls without a null pointer exception, even if the Optional<T> is already empty:

```java
@Test
public void optional_composingMultipleCalls() {
    Double negative = -1.0;
    Optional<Double> emptySqrt = sqrt(negative);
    Optional<Double> doesntBlowUp = emptySqrt.flatMap(this::log);

    assertFalse(emptySqrt.isPresent());
    assertFalse(doesntBlowUp.isPresent());
}

```
