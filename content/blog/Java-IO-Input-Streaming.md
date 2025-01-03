---
title: "Java IO: Input Streaming"
date: 2018-11-03T12:00:01
draft: false
---

The sample code associated with this post can be found [on Github](https://github.com/nfisher23/iodemos).

In Java, the input and output stream abstraction can be used with file systems or across networks. While a lot of these abstractions have been abstracted even further
away with modern libraries and tools (via servlets, for example), understanding the basics makes solving things like performance issues a little easier to wrap your head around.

To begin with, opening a stream takes up operating system resources, so you have to be careful to close those resources after you open them. Before Java 8 was introduced, you would have
had to have closed the resource using a try/finally block, like:

```java
InputStream inputStream =
    new FileInputStream(simpleExampleFilePath);
try {
    int readValue = inputStream.read();
} finally {
    inputStream.close();
}

```

Thankfully, this awkward looking block was improved in Java 8 to [try-with-resources](https://docs.oracle.com/javase/tutorial/essential/exceptions/tryResourceClose.html). To get an automatic close of resources, even in the case of an exception, you can change the above to:

```java
try (InputStream inputStream =
        new FileInputStream(simpleExampleFilePath)) {
    int readValue = inputStream.read();
}

```

Now, let&#39;s say we have a file that has a single line, in UTF-8 format:

```
1 this is some text
```

We can access that file in a primitive way using an InputStream:

```java
@Test
public void fileInputStream_ex() throws Exception {
    try (InputStream fileInputStream = new FileInputStream(simpleExampleFilePath)) {
        assertEquals(&#39;t&#39;, fileInputStream.read());
        assertEquals(&#39;h&#39;, fileInputStream.read());
        assertEquals(&#39;i&#39;, fileInputStream.read());
        assertEquals(&#39;s&#39;, fileInputStream.read());
    }
}

```

Where `simpleExampleFilePath` is a string containing the _relative_ path to the file. We compare the character values with the read integer values above because they are equivalent on a byte level.

You can also work with double values, if desired, by enriching the InputStream into a DataInputStream:

```java
@Test
public void dataInputStream_ex() throws Exception {
    try (InputStream fileInputStream = new FileInputStream(simpleExampleFilePath);
            DataInputStream dataInputStream = new DataInputStream(fileInputStream)) {
            // &#34;This method is suitable for reading bytes written by the writeDouble method of interface DataOutput&#34;
            // namely--this is not the right application
            double readValue = dataInputStream.readDouble();
            assertTrue(readValue &gt; 0);
    }
}

```

As you can see from the comment, the DataInputStream is usually only really useful when you&#39;re reading double values that were previously written using the writeDouble method from the DataOutput interface.

The problem with both of those examples is the default for InputStream, which requests data from the operating system one byte at a time. This is much more costly than asking for a &#34;chunk&#34; of bytes at a time, reading them into memory once, then processing them after they are loaded into memory. This process is called _buffering_, and it is accomplished in Java using the BufferedInputStream:

```java
@Test
public void bufferingData_ex() throws Exception {
    try (InputStream fileInputStream = new FileInputStream(simpleExampleFilePath)) {
        try (BufferedInputStream bufferedInputStream = new BufferedInputStream(fileInputStream)) {

            final int totalAvailable = bufferedInputStream.available();
            String expectedText = &#34;this is some text&#34;;
            for (int i = 0; i &lt; totalAvailable; i&#43;&#43;) {
                int read = bufferedInputStream.read();
                System.out.println((char)read);
                assertEquals(expectedText.charAt(i), read);
            }

        }
    }
}

```

[Buffering is usually much faster](https://nickolasfisher.com/blog/Improving-Java-IO-Performance-Buffering-Techniques) than requesting all data a byte at a time. The default buffer size is 8192 bytes--this number should be changed if you have a reasonable idea as to the size of the file and how much of the file you actually need to process. [Tweak and tinker with benchmarks](https://nickolasfisher.com/blog/Improving-Java-IO-Performance-Buffering-Techniques) liberally if performance is important.

Finally, sometimes we want to &#34;peek&#34; the next byte into memory, which we can&#39;t do with a normal InputStream. We can move forward and backward with a I/O stream using the `PushbackInputStream`:

```java
@Test
public void pushbackInputStream_ex() throws Exception {
    try (InputStream fileInputStream = new FileInputStream(simpleExampleFilePath)) {
        try (DataInputStream dataInputStream = new DataInputStream(fileInputStream)) {
            try (PushbackInputStream pushbackInputStream = new PushbackInputStream(dataInputStream)) {
                assertEquals(&#39;t&#39;, pushbackInputStream.read());
                pushbackInputStream.unread(&#39;t&#39;);
                assertEquals(&#39;t&#39;, pushbackInputStream.read());
            }
        }
    }
}

```
