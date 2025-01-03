---
title: "Subscribing to Redis Channels with Java, Spring Boot, and Lettuce"
date: 2021-04-24T20:05:52
draft: false
tags: [java, spring, reactive, webflux, lettuce, redis]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Pub/Sub in redis allows a publisher to send things to subscribers without knowing who is actually subscribed. In a previous post, we covered [a simple unit test for publishing and subscribing to lettuce](https://nickolasfisher.com/blog/How-to-Publish-and-Subscribe-to-Redis-Using-Lettuce), but if you want to have a subscription initialized on application startup, and respond to events, we&#39;ll have to do a bit more, which I&#39;ll demonstrate here.

### Subscribing on Application Startup

We will want to make sure we have [the right configuration to connect to redis using lettuce](https://nickolasfisher.com/blog/How-to-Configure-Lettuce-to-connect-to-a-local-Redis-Instance-with-Webflux) with something like:

```java
@Configuration
public class RedisConfig {

    @Bean(&#34;redis-primary-client&#34;)
    public RedisClient redisClient(RedisPrimaryConfig redisPrimaryConfig) {
        return RedisClient.create(
                // adjust things like thread pool size with client resources
                ClientResources.builder().build(),
                &#34;redis://&#34; &#43; redisPrimaryConfig.getHost() &#43; &#34;:&#34; &#43; redisPrimaryConfig.getPort()
        );
    }
}

```

Where our **RedisPrimaryConfig** looks like:

```java
@Configuration
@ConfigurationProperties(prefix = &#34;redis-primary&#34;)
public class RedisPrimaryConfig {
    private String host;
    private Integer port;

    public String getHost() {
        return host;
    }

    public void setHost(String host) {
        this.host = host;
    }

    public Integer getPort() {
        return port;
    }

    public void setPort(Integer port) {
        this.port = port;
    }
}

```

And our **application.yml** has the host and port \[this example is a locally redis instance\]:

```yaml
redis-primary:
  host: 127.0.0.1
  port: 6379

```

We can then add our **RedisPubSubReactiveCommands** bean to our **RedisConfig** configuration class:

```java
    @Bean(&#34;redis-subscription-commands&#34;)
    public RedisPubSubReactiveCommands&lt;String, String&gt; redisPubSubReactiveCommands(RedisClient redisClient) {
        return redisClient.connectPubSub().reactive();
    }

```

With the boilerplate out of the way, we can finally leverage **@PostConstruct** to subscribe to one or more redis channels of our choosing, just after we initialize our IoC container and just before the application finishes starting up:

```java
@Service
public class RedisSubscriptionInitializer {

    private final Logger LOG = LoggerFactory.getLogger(RedisSubscriptionInitializer.class);

    private final RedisPubSubReactiveCommands&lt;String, String&gt; redisPubSubReactiveCommands;

    public RedisSubscriptionInitializer(RedisPubSubReactiveCommands&lt;String, String&gt; redisPubSubReactiveCommands) {
        this.redisPubSubReactiveCommands = redisPubSubReactiveCommands;
    }

    @PostConstruct
    public void setupSubscriber() {
        redisPubSubReactiveCommands.subscribe(&#34;channel-1&#34;).subscribe();

        redisPubSubReactiveCommands.observeChannels().doOnNext(stringStringChannelMessage -&gt; {
            if (&#34;channel-1&#34;.equals(stringStringChannelMessage.getChannel())) {
                LOG.info(&#34;found message in channel 1: {}&#34;, stringStringChannelMessage.getMessage());
            }
        }).subscribe();
    }
}

```

In this case, we&#39;re just logging all the messages we get from **channel-1**, you could obviously introduce whatever code you want there \[you could also do something other than **doOnNext**, for example **flatMap**\].

If I start up this application and have my local redis instance up and running, I can:

```bash
$redis-cli publish channel-1 some-message-1
(integer) 1
$redis-cli publish channel-1 some-message-2
(integer) 1

```

Note that the response indicates how many subscribers the message was delivered to. I can then cross check the logs on my application:

```bash
[llEventLoop-5-2] c.n.r.s.RedisSubscriptionInitializer     : found message in channel 1: some-message-1
[llEventLoop-5-2] c.n.r.s.RedisSubscriptionInitializer     : found message in channel 1: some-message-2

```

Then, if I SIGINT the application and try sending another message, I will see that it delivers it to zero subscribers:

```bash
$ redis-cli publish channel-1 some-message-3
(integer) 0

```

So this should be a good starting point for you.
