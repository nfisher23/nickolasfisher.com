---
title: "Optimistic Locking in Redis with Reactive Lettuce"
date: 2021-04-01T00:00:00
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Optimistic Locking in Redis is one of the only reasons to want to use transactions, in my opinion. You can ensure a grouping of atomic operations only occur if a watched key does not change out from underneath you. On the CLI, this might start with:

``` bash
127.0.0.1:6379&gt; SET key1 value1
OK
127.0.0.1:6379&gt; WATCH key1
OK
127.0.0.1:6379&gt; MULTI
OK

```

WATCH is saying &#34;redis, watch key1 for me, and if it changes at all then rollback the transaction I am about to start.&#34; Then we actually start the transaction with MULTI.

Now on this same thread, let&#39;s say we issue two commands before committing \[before the EXEC, command, that is\]:

``` bash
127.0.0.1:6379&gt; SET key2 value2
QUEUED
127.0.0.1:6379&gt; SET key1 newvalue
QUEUED

```

Obviously, because we&#39;re in a transaction, we have not actually &#34;committed&#34; either of these just yet. If we now start up another terminal and run:

``` bash
