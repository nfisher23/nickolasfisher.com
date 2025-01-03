---
title: "Improving Java IO Performance: Formatting Costs"
date: 2018-11-17T18:27:31
draft: false
tags: [java, i/o, performance testing, jmh]
---

The sample code associated with this blog post can be found [on GitHub](https://github.com/nfisher23/io-tuning).

Another potential source of I/O bottlenecks, across any medium, could be the process you choose to format the data in in the first place. For example, XML used to be a standard way to send information across the wire or store in a backend system, but the size overhead of XML as compared to JSON is about double (not to mention it's somehow harder to read when formatted compared to JSON).

We can compare the performance of a couple of different options related to formatting by comparing the MessageFormatter class with simple addition. With a test setup like so:

```java
    public static void runBenchmark(Class clazz) throws Exception {
        Options options = new OptionsBuilder()
                .include(clazz.getName() + ".*")
                .mode(Mode.AverageTime)
                .warmupTime(TimeValue.seconds(1))
                .warmupIterations(2)
                .measurementIterations(2)
                .timeUnit(TimeUnit.MILLISECONDS)
                .measurementTime(TimeValue.seconds(1))
                // OS bottleneck, so we use should one
                // thread at a time for accurate results
                .threads(1)
                .forks(1)
                .shouldFailOnError(true)
                .shouldDoGC(true)
                .build();

        new Runner(options).run();
    }
....
    @Test
    public void launchBenchmark() throws Exception {
        Utils.runBenchmark(this.getClass());
    }

```

We can compare the performance of a MessageFormatter in both a precompiled state and a state that is not precompiled:

```java
    public static int COUNT = 25000;
    public static int NUM = 7;

    @Benchmark
    public void formatUsingMessageFormatter_preCompiled() {
        MessageFormat formatter = new MessageFormat("The square of {0} is {1}\n");
        Integer[] values = new Integer[2];
        values[0] = NUM;
        values[1] = NUM * NUM;
        for (int i = 0; i < COUNT; i++) {
            String s = formatter.format(values);
            System.out.print(s);
        }
    }

    @Benchmark
    public void formatWithoutPrecompiling() {
        String format = "The square of {0} is {1}\n";
        Integer[] values = new Integer[2];
        values[0] = NUM;
        values[1] = NUM * NUM;
        for (int i = 0; i < COUNT; i++) {
            String s = MessageFormat.format(format, values);
            System.out.print(s);
        }
    }

```

The performance of these methods on my machine look like:

```bash
Benchmark                                                     Mode  Cnt    Score   Error  Units
FormattingCostsTests.formatUsingMessageFormatter_preCompiled  avgt    2  275.921          ms/op
FormattingCostsTests.formatWithoutPrecompiling                avgt    2  334.822          ms/op
```

Now, we can achieve the same result using garden variety addition, and compare that to a completely precompiled state:

```java
    @Benchmark
    public void printingWithNoFormattingCosts() {
        for (int i = 0; i < COUNT; i++) {
            System.out.print("The square of 7 is 49\n");
        }
    }

    @Benchmark
    public void formatUsingAddition() {
        for (int i = 0; i < COUNT; i++) {
            String s = "The square of " + NUM + " is " + NUM * NUM + "\n";
            System.out.print(s);
        }
    }

```

The resulting performance of everything together, on my machine, is:

```bash
Benchmark                                                     Mode  Cnt    Score   Error  Units
FormattingCostsTests.formatUsingAddition                      avgt    2   59.710          ms/op
FormattingCostsTests.formatUsingMessageFormatter_preCompiled  avgt    2  275.921          ms/op
FormattingCostsTests.formatWithoutPrecompiling                avgt    2  334.822          ms/op
FormattingCostsTests.printingWithNoFormattingCosts            avgt    2   57.381          ms/op
```

Or, the decision to not use the MessageFormatter class achieved a dramatic (~4 times) performance improvement.
