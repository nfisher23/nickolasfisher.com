---
title: "Improving Java IO Performance: Appropriately Using Random Access Over Streams"
date: 2018-11-01T00:00:00
draft: false
---

The sample code for this blog post can be found [on GitHub](https://github.com/nfisher23/io-tuning).

A flavor I/O performance optimization that applies specifically to the filesystem is the decision on when to use Random Access instead of something like a BufferedInputStream. Random access allows for accessing a file in a similar way as a large array of bytes stored on the filesystem. From the [oracle documentation on the RandomAccessFile class](https://docs.oracle.com/javase/7/docs/api/java/io/RandomAccessFile.html):

&gt; There is a kind of cursor,
&gt; or index into the implied array, called the _file pointer_;
&gt; input operations read bytes starting at the file pointer and advance
&gt; the file pointer past the bytes read.

Instead of reading every byte into memory, then, the cursor-ish implementation will allow us to scan to the next part of the file. In the case where we know the structure of the file and it is quite orderly (e.g. a custom database or csv file with predictable spacing), and when we want to grab specific information out of the file, this provides us with a powerful way to improve performance.

Let&#39;s create a csv file with 100K lines, where each line is 0,1,2,...,8,9:

``` java
    @BeforeClass
    public static void setupLargeCsv() throws Exception {
        Path pathToLargeCsv = Paths.get(Utils.largeCsvFilePath);
        writeCsvFile(Utils.numberOfNewLines_inLargeCsv, pathToLargeCsv);
    }

    private static void writeCsvFile(int numOfLinesToWrite, Path filePath) throws IOException {
        // run once to create the sample data we need for testing
        String csvDataToWrite = getCsv(numberOfNewLines_inSmallCsv);
        Files.write(filePath, csvDataToWrite.getBytes());
    }

    public static String getCsv(int numberOfLines) {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i &lt; numberOfLines; i&#43;&#43;) {
            for (int j = 0; j &lt; 10; j&#43;&#43;) {
                builder.append(Integer.toString(j)).append(&#34;,&#34;);
            }
            builder.replace(builder.length() - 1, builder.length(), &#34;\n&#34;);
        }

        return builder.toString();
    }

```

And set up our benchmark runner with JMH:

``` java
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
....
    @Test
    public void runBenchmark() throws Exception {
        Utils.runBenchmark(this.getClass());
    }

```

Let&#39;s assume we want to stop off and read each character that is 20K characters in. Because of the structure of the csv file, we know that these will all be &#39;0&#39;. If we want to implement that using an InputStream/BufferedInputStream we would do this:

``` java
    public static int INTERVAL = 20000;
    @Benchmark
    public void scanningThroughWithBufferedInputStream() throws Exception {
        try (FileInputStream fileInputStream = new FileInputStream(Utils.largeCsvFilePath);
             BufferedInputStream bufferedInputStream = new BufferedInputStream(fileInputStream)) {
            for (int i = 0; i &lt; 10; i&#43;&#43;) {
                int readVal = bufferedInputStream.read();
                long totalSkipped = 0;
                totalSkipped = bufferedInputStream.skip(INTERVAL - 1);
                while (totalSkipped != INTERVAL - 1) {
                    totalSkipped &#43;= bufferedInputStream.skip(INTERVAL - totalSkipped - 1);
                }

                assertEquals(&#39;0&#39;, readVal);
            }
        }
    }

```

The reason we need to keep skipping is because the bufferedInputStream.skip(..) method does not guarantee it will skip the passed in value, and instead returns the actual amount skipped.

The performance of this method on my machine comes out to:

``` bash
Benchmark                                                 Mode  Cnt  Score   Error  Units
RandomAccessTests.scanningThroughWithBufferedInputStream  avgt    2  0.038          ms/op

```

Conversely, doing that with a RandomAccessFile would look like this:

``` java
    @Benchmark
    public void seekingToPosition() throws Exception {
        try (RandomAccessFile randomAccessFile = new RandomAccessFile(Utils.largeCsvFilePath, &#34;r&#34;)) {
            for (int i = 0; i &lt; 10; i&#43;&#43;) {
                randomAccessFile.seek(INTERVAL);
                int readValue = randomAccessFile.read();
                assertEquals(&#39;0&#39;, readValue);
            }
        }
    }

```

And the performance of both methods run back to back, on my machine, looks like:

``` bash
Benchmark                                                 Mode  Cnt  Score   Error  Units
RandomAccessTests.scanningThroughWithBufferedInputStream  avgt    2  0.038          ms/op
RandomAccessTests.seekingToPosition                       avgt    2  0.019          ms/op
```

Or, by utilizing the RandomAccessFile, we have achieved approximately double the performance improvement.


