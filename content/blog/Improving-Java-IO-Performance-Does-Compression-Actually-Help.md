---
title: "Improving Java IO Performance: Does Compression Actually Help?"
date: 2018-11-17T18:55:03
draft: false
tags: [java, performance testing, jmh]
---

The sample code associated with this blog post can be found [on GitHub](https://github.com/nfisher23/io-tuning).

The question "does compression actually help?" is admittedly pretty loaded. The real answer is _sometimes_, and _it depends_. I will not try to answer every use case, but I will provide a very specific example here that appears to provide a "probably not" answer (for this specific use case).

We'll write a CSV file that contains 1M lines, where each line looks like "0,1,2,3...,8,9". First, I'll set up the benchmark runner JMH with JUnit:

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
...
    @Test
    public void launchBenchmark() throws Exception {
        Utils.runBenchmark(this.getClass());
    }

```

Then I'll set up a benchmark that writes and reads without compression, using the file size as the buffer in the second case:

```java
    public static int NUMBER_OF_CSV_LINES = 1000000;
```

```java
    @Benchmark
    public void readAndWriteWithoutCompression() throws Exception {
        writeUncompressedFileToDisk(Utils.getCsv(NUMBER_OF_CSV_LINES), millionLineCsvFilePath);
        String readValues = readUncompressedFileFromDisk(millionLineCsvFilePath);
        assertTrue(readValues.startsWith("0,1,2,3,4,5"));
    }

    private void writeUncompressedFileToDisk(String data, String fileOutPutPath) throws Exception {
        try (FileOutputStream fileOutputStream = new FileOutputStream(fileOutPutPath)) {
            fileOutputStream.write(data.getBytes());
        }
    }

    private String readUncompressedFileFromDisk(String filePath) throws Exception {
        try (FileInputStream fileInputStream = new FileInputStream(filePath)) {
            int length = (int) new File(filePath).length();
            byte[] bytes = new byte[length];
            fileInputStream.read(bytes);
            return new String(bytes);
        }
    }

```

And I'll set up a comparison benchmark that using compression, specifically using ZipInputStream and ZipOutputStream (using the ZIP algorithm):

```java
    @Benchmark
    public void readAndWriteCompressedData() throws Exception {
        compressAndWriteFile(Utils.getCsv(NUMBER_OF_CSV_LINES), compressedLargeCsvFile);
        String dataFromCompressedFile = readCompressedFile(compressedLargeCsvFile);
        assertTrue(dataFromCompressedFile.startsWith("0,1,2,3,4,5"));
    }

    private void compressAndWriteFile(String data, String fileOutputPath) throws Exception {
        try (FileOutputStream fileOutputStream = new FileOutputStream(fileOutputPath);
             ZipOutputStream zipOutputStream = new ZipOutputStream(fileOutputStream)) {
            ZipEntry zipEntry = new ZipEntry(fileOutputPath);
            zipOutputStream.putNextEntry(zipEntry);
            zipOutputStream.write(data.getBytes());
        }
    }

    private String readCompressedFile(String path) throws Exception {
        try (FileInputStream fileInputStream = new FileInputStream(path);
             ZipInputStream zipInputStream = new ZipInputStream(fileInputStream)) {
            zipInputStream.getNextEntry();
            byte[] buffered = new byte[NUMBER_OF_CSV_LINES * 20];
            zipInputStream.read(buffered);
            return new String(buffered);
        }
    }

```

The performance comparison on my machine between these two approaches came to:

```bash
Benchmark                                        Mode  Cnt    Score   Error  Units
CompressionTests.readAndWriteCompressedData      avgt    2  472.763          ms/op
CompressionTests.readAndWriteWithoutCompression  avgt    2  407.777          ms/op
```

So, in this particular case, it's faster to write normal data size to disk and pull out the same size. However, the advantage of compression in this case could also be that you're saving on disk storage, which could provide value.

I did run these benchmarks on another machine and noticed a ~3 times improvement in _speed_ for compression, so the specific environment is probably important. Like everything else, tinker aggressively with these concepts if you're tasked with optimization.
