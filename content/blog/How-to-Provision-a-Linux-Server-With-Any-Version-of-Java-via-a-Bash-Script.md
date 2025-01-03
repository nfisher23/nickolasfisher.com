---
title: "How to Provision a Linux Server With Any Version of Java via a Bash Script"
date: 2018-10-01T00:00:00
draft: false
---

While we would all like to be up to date, sometimes legacy systems handcuff us into using an older version of software. Java is no exception, and in some cases we
have to resort to using, say, Java 8, instead of the latest version with all of the security updates that we need.

From my scrounging on the internet, it turns out this isn&#39;t an extremely straightforward process via any package manager. Some solutions flat out don&#39;t work on newer
systems. So, it&#39;s in everyone&#39;s best interest to try to understand a little bit more about how a Linux OS works and unpack the tarball from the source.

First, head over to the [OpenJDK archives page](https://jdk.java.net/archive/) and select the link appropriate for your needs.
This tutorial will use Open-JDK 10.0.1, which (as of this writing), has the link:

``` bash
https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz
```

Once you have that, run a wget on your target system:

``` bash
