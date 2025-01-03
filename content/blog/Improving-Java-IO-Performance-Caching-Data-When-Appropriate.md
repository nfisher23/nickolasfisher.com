---
title: "Improving Java IO Performance: Caching Data, When Appropriate"
date: 2018-11-01T00:00:00
draft: false
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/io-tuning).

The biggest bottleneck with I/O resources on the filesystem is the operating system, which controls access to the filesystem. Reading from, and writing to, the operating system, is much more expensive than storing data in memory, and that is the subject of this post: caching.

Caching is the process of storing the result of some operation for later use. For a web application that makes a database query, then parses a template and returns a result, it may be advantageous to cache the result and just pop out that result on the server. In that case, we would be limiting the need to call a relatively expensive operation (first invoking the web application and all its layers, including a database query and a template parsing), by only calling it when it was time to cache (store) the result.

In the case of the filesystem, since our computational bottleneck is the operating system, we may sometimes have need to go over a file&#39;s contents multiple times. If the file is a reasonable size and won&#39;t exceed available memory, it would be advantageous to call the OS once, then use the result of that call whenever a resource needs it.

To prove this principle is faster, let&#39;s set up a JMH test with Junit:

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
    public void launch() throws Exception {
        Utils.runBenchmark(this.getClass());
    }

```

In this first benchmark case, we will iterate ten times over loading a file, and we will make a call to the operating system each time we want the file:

``` java
    @Benchmark
    public void loadWholeFileThenScan() throws Exception {
        for (int i = 0; i &lt; 10; i&#43;&#43;) {
            List&lt;String&gt; linesInFile = readLinesOfFileFromDisk(Utils.smallCsvFilePath);
            assertLinesCorrect(linesInFile);
        }
    }

    private void assertLinesCorrect(List&lt;String&gt; lines) {
        for (String line : lines) {
            assertTrue(line.startsWith(&#34;0,1,2,3,4,5&#34;));
        }
    }

    private List&lt;String&gt; readLinesOfFileFromDisk(String filePath) throws Exception {
        List&lt;String&gt; listofLines = new ArrayList&lt;&gt;();

        try (FileReader fileReader = new FileReader(filePath);
             BufferedReader bufferedReader = new BufferedReader(fileReader)) {
            listofLines.add(bufferedReader.readLine());
        }

        return listofLines;
    }

```

And the comparison case will store the result in memory (caching) and give us the cached copy whenever we ask for it:

``` java
    @Benchmark
    public void loadCachedFilesThenScan() throws Exception {
        for (int i = 0; i &lt; 10; i&#43;&#43;) {
            List&lt;String&gt; linesInFile = getLinesOfFileCached(Utils.smallCsvFilePath);
            assertLinesCorrect(linesInFile);
        }
    }

    private static List&lt;String&gt; cachedLines;

    private List&lt;String&gt; getLinesOfFileCached(String filePath) throws Exception {
        if (cachedLines == null) {
            cachedLines = readLinesOfFileFromDisk(filePath);
        }
        return cachedLines;
    }

```

In this case, the performance of the relative approaches on my machine is:

``` bash
Benchmark                             Mode  Cnt   Score   Error  Units
CachingTests.loadCachedFilesThenScan  avgt    2  ≈ 10⁻⁴          ms/op
CachingTests.loadWholeFileThenScan    avgt    2   0.210          ms/op
```

Or a pretty massive improvement over making repeated OS calls.


