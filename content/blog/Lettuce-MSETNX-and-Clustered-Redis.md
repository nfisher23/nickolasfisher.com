---
title: "Lettuce, MSETNX, and Clustered Redis"
date: 2021-04-17T09:35:41
draft: false
tags: [java, reactive, webflux, lettuce, redis]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

[MSETNX](https://redis.io/commands/msetnx) when you're working with a single redis primary node is simple enough to understand: it sets all of the key/value pairs, or none at all. If one of the keys already exists in the cluster, then all of them are rejected.

With clustered redis, you have more than one node taking writes, and the client is cluster-aware--so if some of the keys are set on one node and some of the keys aren't set on another node, what happens if you try to run **MSETNX**? This post, at least using the lettuce client for clustered redis, finds out.

To start with, ensure you have [set up your locally running redis cluster](https://nickolasfisher.com/blog/bootstrap-a-local-sharded-redis-cluster-in-five-minutes) and have [configured lettuce to connect to clustered redis](https://nickolasfisher.com/blog/configuring-lettucewebflux-to-work-with-clustered-redis). With that in place, we can add some code that runs mset nx on a distributed number of keys:

```java
    private void msetNxDifferentHashSlots() {
        Mono<Boolean> successMono = redisClusterReactiveCommands.msetnx(
            Map.of(
                "key-1", "value-1",
                "key-2", "value-2",
                "key-3", "value-3",
                "key-4", "value-4"
            )
        );

        Boolean wasSuccessful = successMono.block();

        LOG.info("msetnx success response: {}", wasSuccessful);
    }

```

If we run this against a fresh cluster, it's no surprise that we see that the response was successful and that all the keys get set, which is the same behavior we would expect with a single primary redis instance:

```bash
$ for port in 30001 30002 30003; do echo "\nport (therefore node): $port"; redis-cli -p $port -c keys '*'; done

port (therefore node): 30001
1) "key-1"
2) "key-4"

port (therefore node): 30002
1) "key-3"

port (therefore node): 30003
1) "key-2"

```

And the log output:

```bash
msetnx success response: true

```

So, what if we delete one of these keys out of redis?

```bash
$ redis-cli -p 30001 -c del key-4
(integer) 1
$ for port in 30001 30002 30003; do echo "\nport (therefore node): $port"; redis-cli -p $port -c keys '*'; done

port (therefore node): 30001
1) "key-1"

port (therefore node): 30002
1) "key-3"

port (therefore node): 30003
1) "key-2"

```

If we then rerun the same java code, we can see the log says that it is false, leading us to believe that none of them got set as per the documentation:

```bash
msetnx success response: false

```

However, in reality that missing key got set, which is inconsistent with something we'd see for a single primary redis instance:

```bash
$ for port in 30001 30002 30003; do echo "\nport (therefore node): $port"; redis-cli -p $port -c keys '*'; done

port (therefore node): 30001
1) "key-1"
2) "key-4"

port (therefore node): 30002
1) "key-3"

port (therefore node): 30003
1) "key-2"

```

So what gives? Well, similar to the [behavior of MSET in the lettuce client in clustered redis](https://nickolasfisher.com/blog/breaking-down-lettuce-mset-commands-in-clustered-redis), lettuce is calculating the hash slot of each key and sending it to the appropriate node. It's actually sending a **msetnx** command to each node for _each individual hash slot_, not necessarily range of hash slots. If we force the keys to have the same hash slot, we can see behavior that is consistent with the documentation:

```java
    private void msetNxSameHashSlots() {
        Mono<Boolean> successMono = redisClusterReactiveCommands.msetnx(
                Map.of(
                        "{same-hash-slot}.key-1", "value-1",
                        "{same-hash-slot}.key-2", "value-2",
                        "{same-hash-slot}.key-3", "value-3"
                )
        );

        Boolean wasSuccessful = successMono.block();

        LOG.info("msetnx success response: {}", wasSuccessful);
    }

```

If we rerun our same experiment, first running the above code and then deleting one entry:

```java
$ redis-cli -p 30001 -c del {same-hash-slot}.key-2
(integer) 1

```

We can rerun our code over and over again, still see the response as false, and not see the missing key added:

```bash
✗ for port in 30001 30002 30003; do echo "\nport (therefore node): $port"; redis-cli -p $port -c keys '*'; done

port (therefore node): 30001
1) "{same-hash-slot}.key-1"
2) "{same-hash-slot}.key-3"

port (therefore node): 30002
(empty list or set)

port (therefore node): 30003
(empty list or set)

```

Log output is:

```bash
msetnx success response: false

```

**TL;DR**, buyer beware when using msetnx in clustered redis with lettuce, you have to know more than you do with a single redis primary instance.
