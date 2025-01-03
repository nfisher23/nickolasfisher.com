---
title: "Improving Java IO Performance: Reducing Method Call Overhead"
date: 2018-11-17T18:06:13
draft: false
tags: [java, i/o, performance testing, jmh]
---

You can view the sample code associated with this blog post [on GitHub.](https://github.com/nfisher23/io-tuning)

While you can achieve massive improvements in I/O operations via [buffering](https://nickolasfisher.com/blog/Improving-Java-IO-Performance-Buffering-Techniques), another key part of tuning java code in general, which is applicable to I/O bound operations, is method call overhead. Methods that are unnecessarily called repeatedly can bog down operations.

To prove my point, we&#39;ll set up benchmarking via JMH like so:

```java
    public static void runBenchmark(Class clazz) throws Exception {
        Options options = new OptionsBuilder()
                .include(clazz.getName() &#43; &#34;.*&#34;)
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

```

We&#39;ll have a benchmark that uses DataInputStream.readLine(), which calls read() under the hood on each character. Even though we are buffering the data, we are still calling read() on each byte that has already been loaded into memory:

```java
    @Benchmark
    public void readEachCharacterUnderTheHood() throws Exception {
        try (FileInputStream fileInputStream = new FileInputStream(Utils.smallCsvFilePath);
             BufferedInputStream bufferedInputStream = new BufferedInputStream(fileInputStream);
             DataInputStream dataInputStream = new DataInputStream(bufferedInputStream)) {
            int count = 0;
            while (dataInputStream.readLine() != null) {
                count&#43;&#43;;
            }

            assertEquals(Utils.numberOfNewLines_inSmallCsv, count);
        }
    }

```

The performance of this method on my machine is:

```bash
Benchmark                                              Mode  Cnt  Score   Error  Units
MethodCallOverheadTests.readEachCharacterUnderTheHood  avgt    2  1.560          ms/op

```

Conversely, BufferedReader is implemented to buffer the buffer, so that the underlying stream does not get hit with repeated method calls. From the [Oracle documentation on the BufferedReader class](https://docs.oracle.com/javase/8/docs/api/java/io/BufferedReader.html):

&gt; In general, each read request made of a Reader causes a corresponding
&gt; read request to be made of the underlying character or byte stream. It is
&gt; therefore advisable to wrap a BufferedReader around any Reader whose read()
&gt; operations may be costly, such as FileReaders and InputStreamReaders.

And:

&gt; Programs that use DataInputStreams for textual input can be localized by
&gt; replacing each DataInputStream with an appropriate BufferedReader.

So, a benchmark that achieves the same result would look like:

```java
    @Benchmark
    public void faster_usingBufferedReader() throws Exception {
        try (FileReader fileReader = new FileReader(Utils.smallCsvFilePath);
             BufferedReader bufferedReader = new BufferedReader(fileReader)) {
            int count = 0;
            while (bufferedReader.readLine() != null) {
                count&#43;&#43;;
            }

            assertEquals(Utils.numberOfNewLines_inSmallCsv, count);
        }
    }

```

When run back to back, the benchmarks on my machine look like:

```bash
Benchmark                                              Mode  Cnt  Score   Error  Units
MethodCallOverheadTests.faster_usingBufferedReader     avgt    2  0.700          ms/op
MethodCallOverheadTests.readEachCharacterUnderTheHood  avgt    2  1.560          ms/op

```

Or, the BufferedReader is indeed ~2 times as fast.
