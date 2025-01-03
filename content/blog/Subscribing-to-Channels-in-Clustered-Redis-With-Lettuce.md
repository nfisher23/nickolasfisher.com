---
title: "Subscribing to Channels in Clustered Redis With Lettuce"
date: 2021-04-01T00:00:00
draft: false
---

We already know [how to subscribe to redis using lettuce](https://nickolasfisher.com/blog/Subscribing-to-Redis-Channels-with-Java-Spring-Boot-and-Lettuce) when it&#39;s not running in clustered mode. If it&#39;s running in clustered mode, it&#39;s not terribly different, but I did discover one thing that is interesting, which is the subject of this article.

What follows will be much easier to grok if you have already [set up a locally running redis cluster](https://nickolasfisher.com/blog/Bootstrap-a-Local-Sharded-Redis-Cluster-in-Five-Minutes) for testing. And the source code for everything that follows [can be found on github](https://github.com/nfisher23/reactive-programming-webflux).

### Lettuce Configuration

Building off a previous article where we [configured a spring boot webflux application to connect to clustered redis](https://nickolasfisher.com/blog/Configuring-LettuceWebflux-to-work-with-Clustered-Redis), we will need to modify our config slightly to support subscriptions:

``` java
@Configuration
@ConfigurationProperties(&#34;redis-cluster&#34;)
public class LettuceConfig {
    private String host;
    private int port;
...getters and setters...
    @Bean(&#34;redis-cluster-commands&#34;)
    public RedisClusterReactiveCommands&lt;String, String&gt; redisPrimaryReactiveCommands(RedisClusterClient redisClusterClient) {
        return redisClusterClient.connect().reactive();
    }

    @Bean
    public RedisClusterClient redisClient() {
        return RedisClusterClient.create(
                // adjust things like thread pool size with client resources
                ClientResources.builder().build(),
                &#34;redis://&#34; &#43; this.getHost() &#43; &#34;:&#34; &#43; this.getPort()
        );
    }

    @Bean(&#34;redis-cluster-pub-sub&#34;)
    public RedisClusterPubSubReactiveCommands&lt;String, String&gt; redisClusterPubSub(RedisClusterClient redisClusterClient) {
        return redisClusterClient.connectPubSub().reactive();
    }
}

```

We need to add an explicit bean name for **RedisClusterReactiveCommands** because **RedisClusterPubSubReactiveCommands** implements that interface, which will lead to bean clashes in other areas of the code. Let&#39;s also modify the **PostConstructExecutor** to accept both types of beans appropriately:

``` java
@Service
public class PostConstructExecutor {

    private static final Logger LOG = Loggers.getLogger(PostConstructExecutor.class);

    private final RedisClusterReactiveCommands&lt;String, String&gt; redisClusterReactiveCommands;
    private final RedisClusterPubSubReactiveCommands&lt;String, String&gt; redisClusterPubSubReactiveCommands;

    public PostConstructExecutor(@Qualifier(&#34;redis-cluster-commands&#34;) RedisClusterReactiveCommands&lt;String, String&gt; redisClusterReactiveCommands,
                                 @Qualifier(&#34;redis-cluster-pub-sub&#34;) RedisClusterPubSubReactiveCommands&lt;String, String&gt; redisClusterPubSubReactiveCommands) {
        this.redisClusterReactiveCommands = redisClusterReactiveCommands;
        this.redisClusterPubSubReactiveCommands = redisClusterPubSubReactiveCommands;
    }
}

```

With that boilerplate out of the way, we can set up a subscription to any channel we want to in the cluster with:

``` java
    private void subscribeToChannel() {
        List&lt;String&gt; channels = new ArrayList&lt;&gt;();
        for (int i = 1; i &lt;= 100; i&#43;&#43;) {
            channels.add(&#34;channel-&#34; &#43; i);
        }
        redisClusterPubSubReactiveCommands.subscribe(channels.toArray(new String[0]))
                .subscribe();

        redisClusterPubSubReactiveCommands.observeChannels().doOnNext(channelAndMessage -&gt; {
            LOG.info(&#34;channel {}, message {}&#34;, channelAndMessage.getChannel(), channelAndMessage.getMessage());
        }).subscribe();
    }

```

If we start up this app, we are subscribing to channels &#34; **channel-1**&#34;...all the way up to &#34; **channel-100**&#34;. We can publish to any one of these channels using the cli with:

``` bash
$ redis-cli -p 30003 -c PUBLISH channel-10 msg
(integer) 0

```

And we can see in the logs of our currently running service:

``` java
INFO 22744 --- [llEventLoop-5-4] c.n.c.PostConstructExecutor              : channel channel-10, message msg

```

There is one strange thing here though: why does our publish command return 0? It should return the number of subscribers that received a message, which in this case we know is at least \[exactly\] 1.

The answer is probably that lettuce is subscribing to only one node, and redis will take care of it from there. If we publish every message to the node with port 30001 on our machine, we can see that to every published channel we get back a 1:

``` bash
for i in $(seq 1 100); do redis-cli -p 30001 -c publish &#34;channel-$i&#34; &#34;message-$i&#34;; done
(integer) 1
(integer) 1
(integer) 1
(integer) 1
...and on and on

```

Even by changing the config of our lettuce client to first connect to node 30002 does not change this. The key takeaway: make sure your application doesn&#39;t need to know the number of publishers the received a message, or you might see strange behavior.


