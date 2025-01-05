---
title: "Subscribing to Channels in Clustered Redis With Lettuce"
date: 2021-04-25T18:43:42
draft: false
tags: [java, spring, webflux, lettuce, redis]
---

We already know [how to subscribe to redis using lettuce](https://nickolasfisher.com/blog/subscribing-to-redis-channels-with-java-spring-boot-and-lettuce) when it's not running in clustered mode. If it's running in clustered mode, it's not terribly different, but I did discover one thing that is interesting, which is the subject of this article.

What follows will be much easier to grok if you have already [set up a locally running redis cluster](https://nickolasfisher.com/blog/bootstrap-a-local-sharded-redis-cluster-in-five-minutes) for testing. And the source code for everything that follows [can be found on github](https://github.com/nfisher23/reactive-programming-webflux).

### Lettuce Configuration

Building off a previous article where we [configured a spring boot webflux application to connect to clustered redis](https://nickolasfisher.com/blog/configuring-lettucewebflux-to-work-with-clustered-redis), we will need to modify our config slightly to support subscriptions:

```java
@Configuration
@ConfigurationProperties("redis-cluster")
public class LettuceConfig {
    private String host;
    private int port;

...getters and setters...

    @Bean("redis-cluster-commands")
    public RedisClusterReactiveCommands<String, String> redisPrimaryReactiveCommands(RedisClusterClient redisClusterClient) {
        return redisClusterClient.connect().reactive();
    }

    @Bean
    public RedisClusterClient redisClient() {
        return RedisClusterClient.create(
                // adjust things like thread pool size with client resources
                ClientResources.builder().build(),
                "redis://" + this.getHost() + ":" + this.getPort()
        );
    }

    @Bean("redis-cluster-pub-sub")
    public RedisClusterPubSubReactiveCommands<String, String> redisClusterPubSub(RedisClusterClient redisClusterClient) {
        return redisClusterClient.connectPubSub().reactive();
    }
}

```

We need to add an explicit bean name for **RedisClusterReactiveCommands** because **RedisClusterPubSubReactiveCommands** implements that interface, which will lead to bean clashes in other areas of the code. Let's also modify the **PostConstructExecutor** to accept both types of beans appropriately:

```java
@Service
public class PostConstructExecutor {

    private static final Logger LOG = Loggers.getLogger(PostConstructExecutor.class);

    private final RedisClusterReactiveCommands<String, String> redisClusterReactiveCommands;
    private final RedisClusterPubSubReactiveCommands<String, String> redisClusterPubSubReactiveCommands;

    public PostConstructExecutor(@Qualifier("redis-cluster-commands") RedisClusterReactiveCommands<String, String> redisClusterReactiveCommands,
                                 @Qualifier("redis-cluster-pub-sub") RedisClusterPubSubReactiveCommands<String, String> redisClusterPubSubReactiveCommands) {
        this.redisClusterReactiveCommands = redisClusterReactiveCommands;
        this.redisClusterPubSubReactiveCommands = redisClusterPubSubReactiveCommands;
    }
}

```

With that boilerplate out of the way, we can set up a subscription to any channel we want to in the cluster with:

```java
    private void subscribeToChannel() {
        List<String> channels = new ArrayList<>();
        for (int i = 1; i <= 100; i++) {
            channels.add("channel-" + i);
        }
        redisClusterPubSubReactiveCommands.subscribe(channels.toArray(new String[0]))
                .subscribe();

        redisClusterPubSubReactiveCommands.observeChannels().doOnNext(channelAndMessage -> {
            LOG.info("channel {}, message {}", channelAndMessage.getChannel(), channelAndMessage.getMessage());
        }).subscribe();
    }

```

If we start up this app, we are subscribing to channels " **channel-1**"...all the way up to " **channel-100**". We can publish to any one of these channels using the cli with:

```bash
$ redis-cli -p 30003 -c PUBLISH channel-10 msg
(integer) 0

```

And we can see in the logs of our currently running service:

```java
INFO 22744 --- [llEventLoop-5-4] c.n.c.PostConstructExecutor              : channel channel-10, message msg

```

There is one strange thing here though: why does our publish command return 0? It should return the number of subscribers that received a message, which in this case we know is at least \[exactly\] 1.

The answer is probably that lettuce is subscribing to only one node, and redis will take care of it from there. If we publish every message to the node with port 30001 on our machine, we can see that to every published channel we get back a 1:

```bash
for i in $(seq 1 100); do redis-cli -p 30001 -c publish "channel-$i" "message-$i"; done
(integer) 1
(integer) 1
(integer) 1
(integer) 1
...and on and on

```

Even by changing the config of our lettuce client to first connect to node 30002 does not change this. The key takeaway: make sure your application doesn't need to know the number of publishers the received a message, or you might see strange behavior.
