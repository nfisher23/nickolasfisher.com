---
title: "Using Hashtags in Clustered Redis with Lettuce and Webflux"
date: 2021-04-11T16:12:09
draft: false
tags: [java, distributed systems, spring, reactive, webflux, lettuce, redis]
---

In clustered redis, any non hash tagged key can be sent unpredictably \[well, actually predictably, if you know the formula\] to any given primary node in the cluster. The very basic way it works is:

- Put the key in a CRC16 function \[in this case, just being used as a hash function\]
- Modulus the output by 16384 \[magic number used by redis\]
- Use that number to send it to the node responsible for it


Given that the lettuce client can automatically handle many cross-slot commands on your behalf \[for example, [automatically sending chunked MSET commands to the correct node](https://nickolasfisher.com/blog/Breaking-down-Lettuce-MSET-Commands-in-Clustered-Redis)\], it&#39;s usually preferable to just define your key and let the lettuce client take care of it. However, if you find that you want to ensure a group of keys all end up on the same node, you have to use hash tags. To demonstrate, let&#39;s build off of some previous code that [configures lettuce to communicate to clustered redis](https://nickolasfisher.com/blog/Configuring-Lettuce-to-work-with-Clustered-Redis). We can run this code to demonstrate that the little formula to get a key&#39;s hash slot is indeed different depending on the key used:

```java
@Service
public class PostConstructExecutor {

    private static final Logger LOG = Loggers.getLogger(PostConstructExecutor.class);

    private final RedisClusterReactiveCommands&lt;String, String&gt; redisClusterReactiveCommands;

    public PostConstructExecutor(RedisClusterReactiveCommands&lt;String, String&gt; redisClusterReactiveCommands) {
        this.redisClusterReactiveCommands = redisClusterReactiveCommands;
    }

    @PostConstruct
    public void doStuffOnClusteredRedis() {
        hashTagging();
    }

    private void hashTagging() {
        for (int i = 0; i &lt; 10; i&#43;&#43;) {
            String candidateKey = &#34;not-hashtag.&#34; &#43; i;
            Long keySlotNumber = redisClusterReactiveCommands.clusterKeyslot(candidateKey).block();
            LOG.info(&#34;key slot number for {} is {}&#34;, candidateKey, keySlotNumber);
            redisClusterReactiveCommands.set(candidateKey, &#34;value&#34;).block();
        }
    }
}

```

If you run this block of code against your clustered redis, you&#39;ll see an output similar to:

```bash
key slot number for not-hashtag.0 is 11206
key slot number for not-hashtag.1 is 15335
key slot number for not-hashtag.2 is 2948
key slot number for not-hashtag.3 is 7077
key slot number for not-hashtag.4 is 11074
key slot number for not-hashtag.5 is 15203
key slot number for not-hashtag.6 is 2816
key slot number for not-hashtag.7 is 6945
key slot number for not-hashtag.8 is 10958
key slot number for not-hashtag.9 is 15087

```

You can then run this little script against the ports that represent each node in our cluster:

```bash
$ for port in 30001 30002 30003; do echo &#34;\nport (therefore node): $port&#34;; redis-cli -p $port -c keys &#39;*&#39;; done

port (therefore node): 30001
1) &#34;not-hashtag.6&#34;
2) &#34;not-hashtag.2&#34;

port (therefore node): 30002
1) &#34;not-hashtag.7&#34;
2) &#34;not-hashtag.3&#34;

port (therefore node): 30003
1) &#34;not-hashtag.9&#34;
2) &#34;not-hashtag.1&#34;
3) &#34;not-hashtag.4&#34;
4) &#34;not-hashtag.5&#34;
5) &#34;not-hashtag.0&#34;
6) &#34;not-hashtag.8&#34;

```

Okay, so they definitely end up on different nodes as expected, and lettuce did abstract all that away for us. If we want them to all end up on the same node, we can use the aforementioned hash tags. The format is `{something-unique}.actual-key`.

For example, we can change our loop to look something like this:

```java
        for (int i = 0; i &lt; 10; i&#43;&#43;) {
            String candidateHashTaggedKey = &#34;{some:hashtag}.&#34; &#43; i;
            Long keySlotNumber = redisClusterReactiveCommands.clusterKeyslot(candidateHashTaggedKey).block();
            LOG.info(&#34;key slot number for {} is {}&#34;, candidateHashTaggedKey, keySlotNumber);
            redisClusterReactiveCommands.set(candidateHashTaggedKey, &#34;value&#34;).block();
        }

```

And the log output should look nearly exactly like this:

```bash
key slot number for {some:hashtag}.0 is 2574
key slot number for {some:hashtag}.1 is 2574
key slot number for {some:hashtag}.2 is 2574
key slot number for {some:hashtag}.3 is 2574
key slot number for {some:hashtag}.4 is 2574
key slot number for {some:hashtag}.5 is 2574
key slot number for {some:hashtag}.6 is 2574
key slot number for {some:hashtag}.7 is 2574
key slot number for {some:hashtag}.8 is 2574
key slot number for {some:hashtag}.9 is 2574

```

And we can rerun our little shell script--we should see all these keys end up on the same node because they share the same hash slot, which was determined by plugging our hashtag into the hash slot function:

```bash
$ for port in 30001 30002 30003; do echo &#34;\nport (therefore node): $port&#34;; redis-cli -p $port -c keys &#39;*&#39;; done

port (therefore node): 30001
 1) &#34;{some:hashtag}.8&#34;
 2) &#34;{some:hashtag}.6&#34;
 3) &#34;{some:hashtag}.7&#34;
 4) &#34;{some:hashtag}.9&#34;
 5) &#34;{some:hashtag}.1&#34;
 6) &#34;{some:hashtag}.4&#34;
 7) &#34;{some:hashtag}.2&#34;
 8) &#34;{some:hashtag}.0&#34;
 9) &#34;{some:hashtag}.5&#34;
10) &#34;{some:hashtag}.3&#34;

port (therefore node): 30002
(empty list or set)

port (therefore node): 30003
(empty list or set)

```

So that lines up with our intuition and is good news. Some parting thoughts for you to chew on:

- The entire purpose of clustering redis and getting automated sharding and replication on each shard is to horizontally scale compute and memory utilization
- Poorly defined hash tags will cause &#34;clumping&#34; of keys onto a single node, defeating the main purpose of clustering redis in the first place.
- You should only use hash tags when you have a fundamental understanding of how it works and a very good reason for doing so
- If you have a good reason and decide to use them, make sure that you define them so that they have high cardinality--or that there are a large number of distinct hash tags that logically group the right keys together, but don&#39;t overdo it.

And with that, you should be good to go.
