---
title: "The Java Stream API: Generating Fibonacci Numbers"
date: 2018-10-01T00:00:00
draft: false
---

You can find the sample code for this post [on GitHub](https://github.com/nfisher23/java_stream_api_samples).

From the knowledge gained via [creating custom Java Stream objects](https://nickolasfisher.com/blog/The-Java-Stream-API-Creating-Custom-Lazy-Infinite-Streams), we can start
to have a little bit of fun with this. The fibonacci number sequence starts with \[0, 1\], and adds each of the previous two elements to create the next element in the sequence.
This looks like \[0, 1, 1, 2, 3, 5, 8, 13, 21...\], and goes on &#34;forever.&#34; We can thus create a template that computes all Fibonacci numbers by implementing a Supplier&lt;T&gt;. like so:

``` java
import java.util.function.Supplier;

public class SupplyFibonacci implements Supplier&lt;Integer&gt; {

    private int[] lastTwoFibs = {0, 1};

    private boolean returnedFirstFib;
    private boolean returnedSecondFib;

    @Override
    public Integer get() {
        if (!returnedFirstFib) {
            returnedFirstFib = true;
            return 0;
        }

        if (!returnedSecondFib) {
            returnedSecondFib = true;
            return 1;
        }

        int nextFib = lastTwoFibs[0] &#43; lastTwoFibs[1];
        lastTwoFibs[0] = lastTwoFibs[1];
        lastTwoFibs[1] = nextFib;
        return nextFib;
    }
}

```

Which we can validate like so:

``` java
    @Test
    public void validate_fibonacci() {
        List&lt;Integer&gt; tenFibs = Stream.generate(new SupplyFibonacci()).limit(10).collect(Collectors.toList());

        assertEquals(0,tenFibs.get(0).intValue());
        assertEquals(1,tenFibs.get(1).intValue());
        assertEquals(1,tenFibs.get(2).intValue());
        assertEquals(2,tenFibs.get(3).intValue());
        assertEquals(3,tenFibs.get(4).intValue());
        assertEquals(5,tenFibs.get(5).intValue());
    }

```

And we can use that sequence to get any Fibonacci number we want, bounded by the laws of physics and bits. In this case, things start to get wonky around Fibonacci ~50 or so, due to machine precision breaking down:

``` java
    @Test
    public void fibonacciStream_printVals() {
        Stream.generate(new SupplyFibonacci()).peek(System.out::println).limit(25).collect(Collectors.toList());
    }

```


