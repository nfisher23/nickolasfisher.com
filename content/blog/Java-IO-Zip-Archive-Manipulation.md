---
title: "Java IO: Zip Archive Manipulation"
date: 2018-11-03T12:27:15
draft: false
---

The sample code associated with this post can be found [on Github](https://github.com/nfisher23/iodemos).

A [ZIP file format](https://en.wikipedia.org/wiki/Zip_(file_format)) is a compressed, lossless archive of files of files and/or directories. While the content being compressed will matter as to the algorithm&#39;s effectiveness, it is a common way to transfer files among peers, particularly on many windows machines.

Java provides an extension to the `FileOutputStream` called ZipOutputStream, which allows you to write data to a zip directory in the format described above.
Here, we will write any text passed in to a single file (called &#34;some-single-file.txt&#34;) in a zip directory at `fullPath`. The zip directory will be overwritten if it already exists:

```java
private void writeAndZipText(String fullPath, String textToWrite) throws Exception {
    try (FileOutputStream fileOutputStream = new FileOutputStream(fullPath)) {
        try (ZipOutputStream zipOutputStream = new ZipOutputStream(fileOutputStream)) {
            ZipEntry zipEntry = new ZipEntry(&#34;some-single-file.txt&#34;);
            zipOutputStream.putNextEntry(zipEntry);

            for (int charIndex = 0; charIndex &lt; textToWrite.length(); charIndex&#43;&#43;) {
                zipOutputStream.write(textToWrite.charAt(charIndex));
            }

            zipOutputStream.closeEntry();
        }
    }
}
```

We can easily read anything from a zip directory using `ZipFile`. We can read all of the content as a String (by casting each byte value to a character) in sequential order from an entire zip directory like so:

```java
private String readAllTextFromZip(String fullPath) throws Exception {
    StringBuilder builder = new StringBuilder();
    try (ZipFile zipFile = new ZipFile(fullPath)) {
        Enumeration&lt;? extends ZipEntry&gt; what = zipFile.entries();
        while (what.hasMoreElements()) {
            ZipEntry zipEntry = what.nextElement();
            try (InputStream inputStream = zipFile.getInputStream(zipEntry)) {
                while (inputStream.available() != 0) {
                    builder.append((char) inputStream.read());
                }
            }
        }
    }
    return builder.toString();
}

```

We can validate that this works as expected with a simple test:

```java
@Test
public void writeZip() throws Exception {
    String pathToFile = Utils.pathToResources &#43; &#34;zip-output-ex.zip&#34;;
    String textToWrite = &#34;something to zip up&#34;;
    writeAndZipText(pathToFile, textToWrite);

    String allTextWritten = readAllTextFromZip(pathToFile);

    assertEquals(textToWrite, allTextWritten);
}

```
