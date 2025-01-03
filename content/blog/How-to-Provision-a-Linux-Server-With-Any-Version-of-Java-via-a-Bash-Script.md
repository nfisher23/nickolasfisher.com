---
title: "How to Provision a Linux Server With Any Version of Java via a Bash Script"
date: 2018-10-28T14:29:38
draft: false
---

While we would all like to be up to date, sometimes legacy systems handcuff us into using an older version of software. Java is no exception, and in some cases we
have to resort to using, say, Java 8, instead of the latest version with all of the security updates that we need.

From my scrounging on the internet, it turns out this isn&#39;t an extremely straightforward process via any package manager. Some solutions flat out don&#39;t work on newer
systems. So, it&#39;s in everyone&#39;s best interest to try to understand a little bit more about how a Linux OS works and unpack the tarball from the source.

First, head over to the [OpenJDK archives page](https://jdk.java.net/archive/) and select the link appropriate for your needs.
This tutorial will use Open-JDK 10.0.1, which (as of this writing), has the link:

```bash
https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz
```

Once you have that, run a wget on your target system:

```bash
# Get tarball for JDK 10.0.1
wget https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz

```

You&#39;ll also need to create a target directory to actually keep the version of java you&#39;re installing:

```bash
# make java 10 directory
mkdir -p /usr/lib/java10

```

Then unpack the tarball into your freshly minted directory:

```bash
# unpack tarball
tar -C /usr/lib/java10/ -xvzf ./openjdk-10.0.1_linux-x64_bin.tar.gz

```

You&#39;ll need to [update alternatives](https://linux.die.net/man/8/update-alternatives) for Java. Updating alternatives is like creating a hierarchical [symbolic link](https://wiki.debian.org/SymLink). Recall that a symbolic link is just a fake file that points to a real one.

The advantage of updating alternatives is that you can have multiple version in your system and more easily change between all of them, but that&#39;s a subject for another post. Here&#39;s the commands you need:

```bash
# update alternatives
update-alternatives --install /usr/bin/java java /usr/lib/java10/jdk-10.0.1/bin/java 20000
update-alternatives --install /usr/bin/javac javac /usr/lib/java10/jdk-10.0.1/bin/javac 20000

```

Finally, we can verify that this all worked by running:

```bash
# update alternatives
update-alternatives --install /usr/bin/java java /usr/lib/java10/jdk-10.0.1/bin/java 20000
update-alternatives --install /usr/bin/javac javac /usr/lib/java10/jdk-10.0.1/bin/javac 20000

```

We can then package all of this up into a reusable bash script:

```bash
#!/bin/bash

# Get tarball for JDK 10.0.1
wget https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz

# make java 10 directory
mkdir -p /usr/lib/java10

# unpack tarball
tar -C /usr/lib/java10/ -xvzf ./openjdk-10.0.1_linux-x64_bin.tar.gz

# update alternatives
update-alternatives --install /usr/bin/java java /usr/lib/java10/jdk-10.0.1/bin/java 20000
update-alternatives --install /usr/bin/javac javac /usr/lib/java10/jdk-10.0.1/bin/javac 20000

# verify with a version check
java -version

```
