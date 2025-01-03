---
title: "Pre Loading Lua Scripts into Clustered Redis with Lettuce"
date: 2021-04-01T00:00:00
draft: false
---

The source code for what follows [can be found on github](https://github.com/nfisher23/reactive-programming-webflux).

In a previous article, we showed how to [efficiently execute a lua script in redis using lettuce](https://nickolasfisher.com/blog/Pre-Loading-a-Lua-Script-into-Redis-With-Lettuce). To really scale our caching solution horizontally \[and elegantly deal with many scaling headaches\], we will also want to make sure we can execute our lua scripts against clustered redis, which as we&#39;ll see here is pretty straightforward.

### SCRIPT LOAD has to be run against every Node

If you have your [local clustered redis solution up and running](https://nickolasfisher.com/blog/Bootstrap-a-Local-Sharded-Redis-Cluster-in-Five-Minutes), we can poke around with the cli a bit \[note: this assumes your local cluster has three primary nodes with ports 30001-30003\]:

``` bash
➜  ~ redis-cli -p 30001 -c script load &#34;return redis.call(&#39;set&#39;,KEYS[1],ARGV[1],&#39;ex&#39;,ARGV[2])&#34;
&#34;cf4df3d8eb7f521ceb285c6870e5713d79e2bb0b&#34;
➜  ~ redis-cli -p 30002 -c
127.0.0.1:30002&gt; evalsha cf4df3d8eb7f521ceb285c6870e5713d79e2bb0b 1 foo1 bar1 10
-&gt; Redirected to slot [13431] located at 127.0.0.1:30003
(error) NOSCRIPT No matching script. Please use EVAL.
127.0.0.1:30003&gt; evalsha cf4df3d8eb7f521ceb285c6870e5713d79e2bb0b 1 foo2 bar1 105
-&gt; Redirected to slot [1044] located at 127.0.0.1:30001
OK

```

As we can see here, we loaded the script into our node with port 30001, then we tried to call the script for a key that had a hash slot which belonged to the node with port 30003. This resulted in an error because that script was not loaded onto that node. If we picked a node where the key&#39;s hash slot landed it on a node where we already loaded the script, then it was executed without a problem.

Put simply, **you have to pre load your lua script on to each primary node** or you will receive errors.

### Using Lettuce

Lettuce will automatically load your script into each node for you, as we should be able to see from this example:

``` java
   private void scriptLoad() {
        LOG.info(&#34;starting script load&#34;);
        String hashOfScript = redisClusterReactiveCommands.scriptLoad(&#34;return redis.call(&#39;set&#39;,KEYS[1],ARGV[1],&#39;ex&#39;,ARGV[2])&#34;)
                .block();

        redisClusterReactiveCommands.evalsha(hashOfScript, ScriptOutputType.BOOLEAN, new String[]{&#34;foo1&#34;}, &#34;bar1&#34;, &#34;10&#34;).blockLast();

        redisClusterReactiveCommands.evalsha(hashOfScript, ScriptOutputType.BOOLEAN, new String[] {&#34;foo2&#34;}, &#34;bar2&#34;, &#34;10&#34;).blockLast();
        redisClusterReactiveCommands.evalsha(hashOfScript, ScriptOutputType.BOOLEAN, new String[] {&#34;foo4&#34;}, &#34;bar4&#34;, &#34;10&#34;).blockLast();
    }

```

This code will run without errors--lettuce loads the script into each node for us, we use the sha returned from redis to tell each node which script to run, and we can sanity check the keys that were set with some cli commands \[note there&#39;s a 10 second expiry on each key--you might want to increase that\]

``` bash
$ redis-cli -p 30002 -c mget foo1
1) &#34;bar1&#34;
$ redis-cli -p 30002 -c mget foo2
1) &#34;bar2&#34;

```

### A Warning

While that code technically works, it&#39;s not uncommon to need to add more nodes to a cluster. Without trying that locally myself, you will want to verify that the new nodes inherit the loaded script. If you don&#39;t \[if redis doesn&#39;t, ultimately\], you will probably suffer a partial outage because you&#39;ll be using a sha for a script that doesn&#39;t exist on that node.

If that does indeed happen, then ensure that your code falls back to re-uploading the script if you get that error response and you should be able to gracefully and silently recover.


