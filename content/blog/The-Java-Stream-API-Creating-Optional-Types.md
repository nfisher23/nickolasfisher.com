---
title: "The Java Stream API: Creating Optional Types"
date: 2018-10-01T00:00:00
draft: false
---

You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

While Optionals are often used in conjunction with the Java Stream API, you can also create your own.
Now, why would you want to do that? Simply put, null pointer exceptions are not a fun time, and embracing optional
types will greatly simplify code development, and prevent premature graying hair.

You can create an Optional with `Optional.of(..)`, `Optional.ofNullable(..)`, or `Optional.empty()`. Let&#39;s say we want to make a
square root method which will ignore values less than zero. Here&#39;s how we might do it:

``` java
private Optional&lt;Double&gt; sqrt(Double num) {
    if (num == null) {
        return Optional.ofNullable(num);
    } else if (num &gt;= 0) {
        return Optional.of(Math.sqrt(num));
    } else {
        return Optional.empty();
    }
}

```

We can test this method works in all three of the scenarios we care about--positive number, negative number, null--like so:

``` java
@Test
public void optional_createPositive_works() {
    Double positive = 8.8;
    Optional&lt;Double&gt; sqrtPositive = sqrt(positive);

    assertTrue(sqrtPositive.isPresent());
}

@Test
public void optional_createNegative_stillWorks() {
    Double negative = -6.5;
    Optional&lt;Double&gt; sqrtNegative = sqrt(negative);

    assertFalse(sqrtNegative.isPresent());
}

@Test
public void optional_createNull_stillWorks() {
    Optional&lt;Double&gt; optionalNull = sqrt(null);
    assertFalse(optionalNull.isPresent());
}

```

To continue down this path, a really neat feature of Optional types is that you can call a chain of methods on them, and if the
optional goes empty at any point during the chain, it won&#39;t blow up. Without optional types, again, a null pointer exception will
blow up your code. Say we wanted to add a logarithm method to our collection of computations:

``` java
private Optional&lt;Double&gt; log(Double num) {
    if (num != null &amp;&amp; num &gt; 0) {
        return Optional.of(Math.log(num));
    } else {
        return Optional.empty();
    }
}

```

We could then chain calls together using the `flatMap(..)` method:

``` java
@Test
public void optional_getsRealValue() {
    Double positive = 1.0;
    Optional&lt;Double&gt; sqrtPositive = sqrt(positive);
    Optional&lt;Double&gt; realVal = sqrtPositive.flatMap(this::log);

    assertEquals(0, realVal.orElseThrow(RuntimeException::new).intValue());
}

```

However, we can still chain together calls without a null pointer exception, even if the Optional&lt;T&gt; is already empty:

``` java
@Test
public void optional_composingMultipleCalls() {
    Double negative = -1.0;
    Optional&lt;Double&gt; emptySqrt = sqrt(negative);
    Optional&lt;Double&gt; doesntBlowUp = emptySqrt.flatMap(this::log);

    assertFalse(emptySqrt.isPresent());
    assertFalse(doesntBlowUp.isPresent());
}

```


