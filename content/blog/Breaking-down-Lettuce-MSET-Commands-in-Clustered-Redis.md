---
title: "Breaking down Lettuce MSET Commands in Clustered Redis"
date: 2021-04-01T00:00:00
draft: false
---

To follow along with this post, it would be best if you have already [set up your local redis cluster](https://nickolasfisher.com/blog/Bootstrap-a-Local-Sharded-Redis-Cluster-in-Five-Minutes) and know how to [connect to a redis cluster and interact with it via Lettuce](https://nickolasfisher.com/blog/Configuring-Lettuce-to-work-with-Clustered-Redis). And the source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

If you are interacting with clustered redis, and you issue an MSET or MGET command directly against a node without a hash tag, you are very likely going to get rejected from the redis node that you&#39;re interacting with unless you get lucky and the hash slot that the keys go into just happen to all go into that single redis node. For example \[assuming you have clustered redis running locally, and one port is 30001\]:

``` bash
$ redis-cli -p 30001 -c
127.0.0.1:30001&gt; MSET &#34;one&#34; 1 &#34;two&#34; 2 &#34;three&#34; 3
(error) CROSSSLOT Keys in request don&#39;t hash to the same slot

```

To solve this problem when you&#39;re interacting using the cli, you typically have to provide a hash tag that prefixes your key. If these are all the same, then redis will use that in the hash slot calculation and put them all on one node:

``` bash
$ redis-cli -p 30001 -c
127.0.0.1:30001&gt; mset {one}first 1 {one}second 2 {one}third 3
-&gt; Redirected to slot [9084] located at 127.0.0.1:30002
OK
127.0.0.1:30002&gt; KEYS *
1) &#34;{one}third&#34;
2) &#34;{one}second&#34;
3) &#34;{one}first&#34;

```

If you&#39;re using lettuce, you might initially think that you have to do the same thing. However, that doesn&#39;t turn out to be the case--lettuce is smart enough to do the hash slot calculation for you before issuing the MSET commands. For example, building off of the configuration we used in our last article:

``` java
@Service
public class PostConstructExecutor {

    private static final Logger LOG = Loggers.getLogger(PostConstructExecutor.class);

    private final RedisClusterReactiveCommands&lt;String, String&gt; redisClusterReactiveCommands;

    public PostConstructExecutor(RedisClusterReactiveCommands&lt;String, String&gt; redisClusterReactiveCommands) {
        this.redisClusterReactiveCommands = redisClusterReactiveCommands;
    }

    @PostConstruct
    public void doStuffOnClusteredRedis() {
        showMsetAcrossCluster();
    }

    private void showMsetAcrossCluster() {
        LOG.info(&#34;starting mset&#34;);

        Map&lt;String, String&gt; map = new HashMap&lt;&gt;();
        for (int i = 0; i &lt; 10; i&#43;&#43;) {
            map.put(&#34;key&#34; &#43; i, &#34;value&#34; &#43; i);
        }

        // can follow with MONITOR to see the MSETs for just that node written, under the hood lettuce breaks
        // up the map, gets the hash slot and sends it to that node for you.
        redisClusterReactiveCommands
                .mset(map)
                .block();
        LOG.info(&#34;done with mset&#34;);
    }
}

```

With this code, we don&#39;t see the same error message. We can further verify that the key/value pairs are actually getting set correctly with a tiny script:

``` bash
$ for port in 30001 30002 30003; do redis-cli -p $port -c keys &#39;*&#39;; done
1) &#34;key7&#34;
2) &#34;key3&#34;
3) &#34;key2&#34;
4) &#34;key6&#34;
1) &#34;key5&#34;
2) &#34;key1&#34;
3) &#34;key9&#34;
1) &#34;key4&#34;
2) &#34;key8&#34;
3) &#34;key0&#34;

```

So what&#39;s happening? Well there are two pretty quick ways to try and find out. The first is to get on a node and run MONITOR:

``` bash
✗ redis-cli -p 30001 -c
127.0.0.1:30001&gt; MONITOR
OK

```

This will hold and send changes to the cluster until you send a SIGINT signal. If I fire up that java/lettuce code from above I see:

``` bash
1618703092.639258 [0 127.0.0.1:45198] &#34;MSET&#34; &#34;key6&#34; &#34;value6&#34;
1618703092.646877 [0 127.0.0.1:45198] &#34;MSET&#34; &#34;key7&#34; &#34;value7&#34;
1618703092.666848 [0 127.0.0.1:45198] &#34;MSET&#34; &#34;key2&#34; &#34;value2&#34;
1618703092.678183 [0 127.0.0.1:45198] &#34;MSET&#34; &#34;key3&#34; &#34;value3&#34;

```

If you then set a debugger on the **mset** command above, you can see that lettuce is actually calculating the hash slot on your behalf \[information it periodically collects from the cluster\], and batches them against the appropriate node on your behalf using pipelining. Pretty cool stuff.


