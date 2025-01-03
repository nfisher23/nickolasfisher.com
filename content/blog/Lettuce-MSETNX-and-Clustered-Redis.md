---
title: "Lettuce, MSETNX, and Clustered Redis"
date: 2021-04-17T09:35:41
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

[MSETNX](https://redis.io/commands/msetnx) when you&#39;re working with a single redis primary node is simple enough to understand: it sets all of the key/value pairs, or none at all. If one of the keys already exists in the cluster, then all of them are rejected.

With clustered redis, you have more than one node taking writes, and the client is cluster-aware--so if some of the keys are set on one node and some of the keys aren&#39;t set on another node, what happens if you try to run **MSETNX**? This post, at least using the lettuce client for clustered redis, finds out.

To start with, ensure you have [set up your locally running redis cluster](https://nickolasfisher.com/blog/Bootstrap-a-Local-Sharded-Redis-Cluster-in-Five-Minutes) and have [configured lettuce to connect to clustered redis](https://nickolasfisher.com/blog/Configuring-LettuceWebflux-to-work-with-Clustered-Redis). With that in place, we can add some code that runs mset nx on a distributed number of keys:

```java
    private void msetNxDifferentHashSlots() {
        Mono&lt;Boolean&gt; successMono = redisClusterReactiveCommands.msetnx(
            Map.of(
                &#34;key-1&#34;, &#34;value-1&#34;,
                &#34;key-2&#34;, &#34;value-2&#34;,
                &#34;key-3&#34;, &#34;value-3&#34;,
                &#34;key-4&#34;, &#34;value-4&#34;
            )
        );

        Boolean wasSuccessful = successMono.block();

        LOG.info(&#34;msetnx success response: {}&#34;, wasSuccessful);
    }

```

If we run this against a fresh cluster, it&#39;s no surprise that we see that the response was successful and that all the keys get set, which is the same behavior we would expect with a single primary redis instance:

```bash
$ for port in 30001 30002 30003; do echo &#34;\nport (therefore node): $port&#34;; redis-cli -p $port -c keys &#39;*&#39;; done

port (therefore node): 30001
1) &#34;key-1&#34;
2) &#34;key-4&#34;

port (therefore node): 30002
1) &#34;key-3&#34;

port (therefore node): 30003
1) &#34;key-2&#34;

```

And the log output:

```bash
msetnx success response: true

```

So, what if we delete one of these keys out of redis?

```bash
$ redis-cli -p 30001 -c del key-4
(integer) 1
$ for port in 30001 30002 30003; do echo &#34;\nport (therefore node): $port&#34;; redis-cli -p $port -c keys &#39;*&#39;; done

port (therefore node): 30001
1) &#34;key-1&#34;

port (therefore node): 30002
1) &#34;key-3&#34;

port (therefore node): 30003
1) &#34;key-2&#34;

```

If we then rerun the same java code, we can see the log says that it is false, leading us to believe that none of them got set as per the documentation:

```bash
msetnx success response: false

```

However, in reality that missing key got set, which is inconsistent with something we&#39;d see for a single primary redis instance:

```bash
$ for port in 30001 30002 30003; do echo &#34;\nport (therefore node): $port&#34;; redis-cli -p $port -c keys &#39;*&#39;; done

port (therefore node): 30001
1) &#34;key-1&#34;
2) &#34;key-4&#34;

port (therefore node): 30002
1) &#34;key-3&#34;

port (therefore node): 30003
1) &#34;key-2&#34;

```

So what gives? Well, similar to the [behavior of MSET in the lettuce client in clustered redis](https://nickolasfisher.com/blog/Breaking-down-Lettuce-MSET-Commands-in-Clustered-Redis), lettuce is calculating the hash slot of each key and sending it to the appropriate node. It&#39;s actually sending a **msetnx** command to each node for _each individual hash slot_, not necessarily range of hash slots. If we force the keys to have the same hash slot, we can see behavior that is consistent with the documentation:

```java
    private void msetNxSameHashSlots() {
        Mono&lt;Boolean&gt; successMono = redisClusterReactiveCommands.msetnx(
                Map.of(
                        &#34;{same-hash-slot}.key-1&#34;, &#34;value-1&#34;,
                        &#34;{same-hash-slot}.key-2&#34;, &#34;value-2&#34;,
                        &#34;{same-hash-slot}.key-3&#34;, &#34;value-3&#34;
                )
        );

        Boolean wasSuccessful = successMono.block();

        LOG.info(&#34;msetnx success response: {}&#34;, wasSuccessful);
    }

```

If we rerun our same experiment, first running the above code and then deleting one entry:

```java
$ redis-cli -p 30001 -c del {same-hash-slot}.key-2
(integer) 1

```

We can rerun our code over and over again, still see the response as false, and not see the missing key added:

```bash
✗ for port in 30001 30002 30003; do echo &#34;\nport (therefore node): $port&#34;; redis-cli -p $port -c keys &#39;*&#39;; done

port (therefore node): 30001
1) &#34;{same-hash-slot}.key-1&#34;
2) &#34;{same-hash-slot}.key-3&#34;

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
