---
title: "The Java Stream API: How to Work With Optional Types"
date: 2018-10-20T21:59:38
draft: false
---

You can find the sample code associated with this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

If Java programmers had a generic Facebook page, they would collectively have an &#34;it&#39;s complicated&#34; relationship with the null value.

Constantly having to check for null values can certainly be a real boon, both in the readability of your code as well as in the hidden implication that not
checking for null means something might blow up. Of course, you could enforce contracts that say to never return null, but there are unfortunately, valid use cases for null.
For example, if you query for an Account using a primary key and there is no account in the database, letting the method responsible for that
return an empty Account value would be disingenuous--it&#39;s not that the Account had empty fields, after all, but that there wasn&#39;t an Account at all.

The Java Stream API has provided a thoughtful solution to this problem through its Optional&lt;T&gt; type. The Optional&lt;T&gt; types allows us to more easily
specify behavior that we want to take place if a value exists or not.

For example, working with our familiar set of names:

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

We can select the last element, sorted by case, with the
max(String::comparingToIgnoreCase) declaration. When we do that, we get an Optional:

```java
Optional&lt;String&gt; maxName = names.stream().max(String::compareToIgnoreCase);

```

Now, if we didn&#39;t get a maximum name--which might happen if the collection were empty--the Optional would be empty. But if we did, the Optional would contain a value.
One way to deal with that is with the `OrElse(..)` method, which says &#34;if there is a value in the Optional, give me that value. If there is not a value in the Optional, then give me the value I pass in
to the OrElse method:

```java
@Test
public void optional_max() {
    Optional&lt;String&gt; maxName = names.stream().max(String::compareToIgnoreCase);

    assertEquals(&#34;Josephine&#34;, maxName.orElse(&#34;&#34;));
}

```

Above, we can see that Josephine is the max string, i.e. the one last alphabetically in the collection. But what if there is no value? The behavior is predictable:

```java
@Test
public void optional_orElse() {
    Optional&lt;String&gt; doesntExist = names.stream().filter(name -&gt; name.startsWith(&#34;Z&#34;)).findAny();

    assertEquals(&#34;default&#34;, doesntExist.orElse(&#34;default&#34;));
}

```

Sometimes, if the Optional&lt;T&gt; is empty, we want to run a method that generates a value for use. We can do that with `OrElseGet(..)`,
which takes a Supplier&lt;T&gt;. Here, we will compute the current time value as a String:

```java
@Test
public void optional_orElseGet() {
    Optional&lt;String&gt; doesntExist = names.stream().filter(name -&gt; name.startsWith(&#34;Z&#34;)).findAny();

    String stringTime = doesntExist.orElseGet(() -&gt; Instant.now().toString());

    System.out.println(stringTime);
}

```

If we don&#39;t get a value in an Optional, we might want to throw a custom exception. Without Optionals, our code would just throw a
NullPointerException, which might be too vague for us to easily find a solution to. We can throw a custom exception with
`OrElseThrow(..)`. Here, we will throw a RuntimeException:

```java
@Test(expected = RuntimeException.class)
public void optional_orElseThrow() {
    Optional&lt;String&gt; doesntExist = names.stream().filter(name -&gt; name.startsWith(&#34;Z&#34;)).findAny();

    doesntExist.orElseThrow(() -&gt; new RuntimeException(&#34;No names starting with &#39;Z&#39; in the collection&#34;));
}
```

Perhaps the most useful of the methods we can run on an Optional&lt;T&gt; is `ifPresent(..)`. `ifPresent(..)` runs only if the Optional
contains a value, does nothing otherwise, and it takes a Consumer&lt;T&gt;. If we have a real simple Consumer that simply saves the value you
pass into it:

```java
private class SimpleConsumer implements Consumer&lt;String&gt; {
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
    Optional&lt;String&gt; alan = names.stream().filter(name -&gt; name.equals(&#34;Alan&#34;)).findFirst();

    SimpleConsumer shouldRun = new SimpleConsumer();
    alan.ifPresent(shouldRun);

    assertEquals(&#34;Alan&#34;, shouldRun.internalValue);
}

```

Whereas it does nothing if there isn&#39;t a value:

```java
@Test
public void optional_ifPresent_DNE() {
    Optional&lt;String&gt; notHere = names.stream().filter(name -&gt; name.equals(&#34;Not a Real Name&#34;)).findFirst();

    notHere.ifPresent(name -&gt; { throw new RuntimeException(&#34;this exception won&#39;t get thrown&#34;); });
}

```

There are other methods we can run on Optionals as well, which have parallel concepts to Streams. In many ways, it&#39;s fair to think of
an Optional&lt;T&gt; as a Stream with zero or one elements. We can map the value, if there is one, like so:

```
@Test
public void optional_map() {
    Optional&lt;String&gt; alan = names.stream().filter(name -&gt; name.equals(&#34;Alan&#34;)).findFirst();

    Optional&lt;String&gt; firstChar = alan.map(name -&gt; name.substring(0, 1));

    assertEquals(&#34;A&#34;, firstChar.orElseThrow(RuntimeException::new));
}

```
