---
title: "Java IO: Creating and Traversing Files And Directories"
date: 2018-11-03T14:36:55
draft: false
---

You can view the sample code associated with this post [on Github](https://github.com/nfisher23/iodemos)

Using the static methods in the `Files` class, a member of the `java.nio.file` package, we can manipulate the file system reasonably easily.

We can create an input stream, in exactly the same way as we do with an explicit constructor, like:

```java
@Test
public void files_inputStreaming() throws Exception {
    Path pathToExampleFile = Paths.get(Utils.simpleExampleFilePath);

    try (InputStream inputStream = Files.newInputStream(pathToExampleFile)) {
        int readValue = inputStream.read();

        assertEquals(&#39;t&#39;, readValue);
    }
}
```

You can create a directory with the `Files.createDirectory(..)` method:

```java
@Test
public void creatingDirsAndFiles_ex() throws Exception {
    Path pathToNewDir = Paths.get(Utils.pathToResources &#43; &#34;new-directory-to-create&#34;);

    Files.deleteIfExists(pathToNewDir);

    assertFalse(Files.isDirectory(pathToNewDir));

    Files.createDirectory(pathToNewDir);

    assertTrue(Files.isDirectory(pathToNewDir));
}

```

If you have a directory beneath other directories that you want to create which do not already exist, like `parent/child/otherchild`, where child does not exist, the above attempt will fail. Make a simple change to `createDirectories(..)` and the method will take care of that for you:

```java
@Test
public void creatingDirectories_intermediateParentDirectories() throws Exception {
    Path newChainedPath = Paths.get(Utils.pathToResources &#43; &#34;parent-dir/sub-dir&#34;);

    Files.deleteIfExists(newChainedPath);

    assertFalse(Files.isDirectory(newChainedPath));

    Files.createDirectories(newChainedPath);

    assertTrue(Files.isDirectory(newChainedPath));
}

```

We can ask for metadata about files with `readAttributes(..)`:

```java
@Test
public void files_getAttributes() throws Exception {
    Path toExistingFile = Paths.get(Utils.simpleExampleFilePath);

    BasicFileAttributes attributes = Files.readAttributes(toExistingFile, BasicFileAttributes.class);

    assertTrue(attributes.isRegularFile());
    assertEquals(17, attributes.size());
}

```

We can access all of the `Path` s immediately beneath a directory with `Files.list(..)`:

```java
@Test
public void visitingDirectories_ex() throws Exception {
    try (Stream&lt;Path&gt; entries = Files.list(Paths.get(Utils.pathToResources))) {
        System.out.println(&#34;counting via list&#34;);
        long count = entries.peek(System.out::println).count();
        assertTrue(count &gt; 0);
    }
}

```

The above method will only list the immediate children. If you want to see all the `Path` s recursively, through each child directory, you&#39;ll need to use `Files.walk(..)`:

```java
@Test
public void visitingDirectories_walkSubDirectories() throws Exception {
    try (Stream&lt;Path&gt; entries  = Files.walk(Paths.get(Utils.pathToResources))) {
        System.out.println(&#34;counting via walk&#34;);
        long count = entries.peek(System.out::println).count();
        assertTrue(count &gt; 0);
    }
}

```
