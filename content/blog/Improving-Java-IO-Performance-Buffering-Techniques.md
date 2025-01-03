---
title: "Improving Java IO Performance: Buffering Techniques "
date: 2018-11-10T12:45:54
draft: false
tags: [java, i/o, performance testing, jmh]
---

﻿You can view the sample code associated with this post [on GitHub](https://github.com/nfisher23/io-tuning).

Now that we know [how to benchmark using junit and jmh](https://nickolasfisher.com/blog/How-to-Benchmark-Java-Code-Using-JUnit-and-JMH), let's put it to the test and try to optimize some basic I/O operations. While filesystem tasks are much less common in the web-enabled world, understanding the basics can help us when we move on to streams across network connections.

First, we'll create a file to read from. I opt to make a comma separated variable (csv) file that has 10,000 lines of 1,2,3...,8,9:

```java
private static String pathToResources = "src/test/resources";
private static String csvFilePath = pathToResources + "/simple-csv-file.csv";

private static final int numberOfNewlines = 10000;

@Before
public void setupFile() throws Exception {
    Path csvPathAsPath = Paths.get(csvFilePath);
    // run once to create the sample data we need for testing
    StringBuilder builder = new StringBuilder();
    for (int i = 0; i < numberOfNewlines; i++) {
        for (int j = 0; j < 10; j++) {
            builder.append(Integer.toString(j)).append(",");
        }
        builder.replace(builder.length() - 1, builder.length(), "\n");
    }

    String csvDataToWrite = builder.toString();
    Files.write(csvPathAsPath, csvDataToWrite.getBytes());
}
```

Then we have to configure the options we want to run the tests under, and put it inside a JUnit test so that it runs on build time:

```java
@Test
public void launchBenchmark() throws Exception {
    Options opt﻿ions = new OptionsBuilder()
            .include(this.getClass().getName() + ".*")
            .mode(Mode.AverageTime)
            .warmupTime(TimeValue.seconds(1))
            .warmupIterations(2)
            .measurementIterations(2)
            .measurementTime(TimeValue.seconds(1))
            // since we are doing read input, which is an
            // OS bottleneck, we have to ensure
            // we use one thread at a time
            .threads(1)
            .forks(1)
            .shouldFailOnError(true)
            .shouldDoGC(true)
            .build();

    new Runner(options).run();
}

```

Now for some theory. As it turns out, when we ask for bytes from the file system, under the hood Java is asking the operating system to perform the action for us. Since OS's control files, it's not possible for Java to act any other way.

When we ask for bytes from the OS, it's a fairly expensive operation end to end. That is, it's expensive to _start_ asking for bytes, but it's not expensive _while_ we are asking for bytes. From this idea, buffering was born. Buffering is basically picking up a chunk of bytes at one time from the operating system rather than asking for one at a time, which is (in theory) much slower if you want to read a bunch of bytes.

This benchmarked-method asks the OS to get us a byte with each call to `read()`:

```java
@Benchmark
@OutputTimeUnit(TimeUnit.MILLISECONDS)
public void noBuffering() throws Exception {
    try (FileInputStream fileInputStream = new FileInputStream(csvFilePath)) {
        int count = countNewLinesUsingStream(fileInputStream);
        assertEquals(numberOfNewlines, count);
    }
}

private int countNewLinesUsingStream(InputStream inputStream) throws Exception {
    int count = 0;
    int bytesRead;
    while ((bytesRead = inputStream.read()) != -1) {
        if (bytesRead == '\n') {
            count++;
        }
    }
    return count;
}
```

The output on the benchmark on my machine from this method is:

```bash
Benchmark                                      Mode  Cnt    Score   Error  Units
BufferingBenchmarkTests.noBuffering            avgt    2  170.308          ms/op
```

So on two tries (after the warmups) we averaged 170 milliseconds per try. Now we will use Java's built in BufferedInputStream:

```java
@Benchmark
@OutputTimeUnit(TimeUnit.MILLISECONDS)
public void defaultJavaBuffering() throws Exception {
    try (FileInputStream fileInputStream = new FileInputStream(csvFilePath);
            BufferedInputStream bufferedInputStream = new BufferedInputStream(fileInputStream)) {
        int count = countNewLinesUsingStream(bufferedInputStream);
        assertEquals(numberOfNewlines, count);
    }
}

```

The benchmark output on my machine is:

```bash
Benchmark                                      Mode  Cnt    Score   Error  Units
BufferingBenchmarkTests.defaultJavaBuffering   avgt    2    0.693          ms/op
```

So, by just adding a line of code (which automatically loads a chunk--8192 bytes as of this writing--of bytes at a time), we have increased our performance by ~245 times. Pretty crazy, but we can do even better. We can implement our own custom buffering code, which uses an array to store the buffered bytes in memory:

```java
@Benchmark
@OutputTimeUnit(TimeUnit.MILLISECONDS)
public void manualBufferingInCode() throws Exception {
    try (FileInputStream fileInputStream = new FileInputStream(csvFilePath)) {
        int count = countNewLinesManually(fileInputStream, 8192);
        assertEquals(numberOfNewlines, count);
    }
}

private int countNewLinesManually(InputStream inputStream, int customBytesToBuffer) throws Exception {
    byte buff[] = new byte[customBytesToBuffer];
    int count = 0;
    int bytesRead;
    while ((bytesRead = inputStream.read(buff)) != -1) {
        for (int i = 0; i < bytesRead; i++) {
            if (buff[i] == '\n') {
                count++;
            }
        }
    }
    return count;
}

```

The benchmark results are:

```bash
Benchmark                                      Mode  Cnt    Score   Error  Units
BufferingBenchmarkTests.manualBufferingInCode  avgt    2    0.148          ms/op

```

Or a ~4.5 times performance improvement over our previous improvement, despite the fact that we used the same buffer size as is the default as of this writing (8192 bytes). We can try to make it even faster, though the results vary from machine to machine, by insisting that the buffer size be the size of the file. The obvious potential problem with this approach is that the file could be larger than the amount of available resources, which would seriously gum up the works:

```java
@Benchmark
@OutputTimeUnit(TimeUnit.MILLISECONDS)
public void useFileSizeAsBuffer() throws Exception {
    int lengthOfFile = (int)(new File(csvFilePath).length());
    try (FileInputStream fileInputStream = new FileInputStream(csvFilePath)) {
        int count = countNewLinesManually(fileInputStream,lengthOfFile);
        assertEquals(numberOfNewlines, count);
    }
}

```

The results of all these operations taken together, on my machine, look like:

```bash
Benchmark                                      Mode  Cnt    Score   Error  Units
BufferingBenchmarkTests.defaultJavaBuffering   avgt    2    0.693          ms/op
BufferingBenchmarkTests.manualBufferingInCode  avgt    2    0.148          ms/op
BufferingBenchmarkTests.noBuffering            avgt    2  170.308          ms/op
BufferingBenchmarkTests.useFileSizeAsBuffer    avgt    2    0.188          ms/op
```
