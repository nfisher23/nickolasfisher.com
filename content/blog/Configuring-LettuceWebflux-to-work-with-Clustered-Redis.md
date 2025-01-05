---
title: "Configuring Lettuce/Webflux to work with Clustered Redis"
date: 2021-04-10T22:27:54
draft: false
tags: [spring, reactive, webflux, lettuce, redis]
---

Lettuce has some pretty nice out of the box support for working with clustered redis. This combination--a reactive client and application along with clustered redis--is about as scalable, performant, and resilient as things can get in distributed systems \[though there are other tradeoffs which are not the subject of this post\].

Demonstrating some basic configuration to make these two systems play nice will be the subject of this post.

To follow along here, you're going to want to make sure you have [set up a locally running sharded redis cluster](https://nickolasfisher.com/blog/bootstrap-a-local-sharded-redis-cluster-in-five-minutes). With that in place, steps to get lettuce working against it in a pretty seamless way are as follows.

First, add lettuce to your **pom.xml**:

```xml
        <dependency>
            <groupId>io.lettuce</groupId>
            <artifactId>lettuce-core</artifactId>
            <version>6.1.0.RELEASE</version>
        </dependency>

```

Then add some configuration that sets up a **RedisClusterClient** and **RedisClusterReactiveCommands**: bean

```java
@Configuration
@ConfigurationProperties("redis-cluster")
public class LettuceConfig {
    private String host;
    private int port;

    public String getHost() {
        return host;
    }

    public void setHost(String host) {
        this.host = host;
    }

    public int getPort() {
        return port;
    }

    public void setPort(int port) {
        this.port = port;
    }

    @Bean
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
}

```

And change your **application.yml** so that this config can actually work:

```yaml
redis-cluster:
  host: 127.0.0.1
  port: 30001

```

Note that I've chosen port **30001** because that's a primary node in my clustered redis configuration that was started up via the last post. Be sure to make sure that this config matches up with at least one of the nodes in your cluster \[it doesn't matter which one, for the sake of this tutorial\]

Now let's actually use this to write some data to our redis cluster:

```java
@Service
public class PostConstructExecutor {
    private final RedisClusterReactiveCommands<String, String> redisClusterReactiveCommands;

    public PostConstructExecutor(RedisClusterReactiveCommands<String, String> redisClusterReactiveCommands) {
        this.redisClusterReactiveCommands = redisClusterReactiveCommands;
    }

    @PostConstruct
    public void doStuffOnClusteredRedis() {
        SetArgs setArgs = new SetArgs();
        setArgs.ex(Duration.ofSeconds(10));
        Mono<String> command = Mono.empty();
        for (int i = 0; i < 10; i++) {
            command = command.then(redisClusterReactiveCommands.set("hello-" + i, "no " + i, setArgs));
        }
        command.block();
    }
}

```

When you start up this application, our chained set of commands will create 10 redis key/value pairs which are just strings, for example " **hello-1" -> "no 1"**. It also, critically, sets the expiry of each of the items that we add in there to 10 seconds. If you start up this application, the **@PostConstruct** method will run and add those key/value pairs to the cluster.

We can verify that with a simple script that iterates through each primary instance in our cluster and runs a "KEYS \*", like so:

```bash
$ for port in 30001 30002 30003; do redis-cli -p $port -c keys '*'; done
1) "hello-0"
2) "hello-8"
3) "hello-4"
1) "hello-1"
2) "hello-5"
3) "hello-2"
4) "hello-6"
5) "hello-9"
1) "hello-7"
2) "hello-3"

```

Again, if your port numbers for your local clustered redis are different, then you should use those instead of **30001 30002 30003**. And with this, you should be good to go.
