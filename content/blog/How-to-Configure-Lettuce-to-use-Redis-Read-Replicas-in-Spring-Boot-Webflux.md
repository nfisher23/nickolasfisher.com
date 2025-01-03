---
title: "How to Configure Lettuce to use Redis Read Replicas in Spring Boot Webflux"
date: 2021-03-28T19:22:27
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Lettuce supports reading from redis replicas, but with the caveat that it doesn&#39;t \[out of the box\] provide you with the fine-grained control over _when_ to read from the replicas that you&#39;re likely to want.

You can, as the documentation states, just set up your redis client like so:

```java
    public RedisStringReactiveCommands&lt;String, String&gt; redisReplicaReactiveCommands(RedisConfig redisConfig) {
        RedisURI redisPrimaryURI = RedisURI.builder()
                .withHost(redisConfig.getHost())
                .withPort(redisConfig.getPort())
                .build();

        RedisClient redisClient = RedisClient.create(
                redisPrimaryURI
        );

        StatefulRedisMasterReplicaConnection&lt;String, String&gt; primaryAndReplicaConnection = MasterReplica.connect(
                redisClient,
                StringCodec.UTF8,
                redisPrimaryURI
        );

        primaryAndReplicaConnection.setReadFrom(ReadFrom.REPLICA);

        return primaryAndReplicaConnection.reactive();
    }

```

But what if you have parts of your application where eventual consistency can be tolerated, but parts of your application require strong consistency? If you have no call-by-call control over whether you&#39;re reading from the primary or replica, this is going to be impossible. We will walk through the extra steps you&#39;ll need to do to get that fine grained consistency in this article

### Local Leader/Follower Redis

Let&#39;s start by reusing work from a previous post where we set up a redis leader/follower setup. We leveraged docker/docker compose, where our **docker-compose.yaml** looked like this:

```yaml
version: &#39;3.8&#39;

services:
  leader:
    image: redis
    ports:
      - &#34;6379:6379&#34;
      - 6379
    networks:
      - local
  follower:
    image: redis
    ports:
      - &#34;6380:6379&#34;
      - 6379
    networks:
      - local
    command: [&#34;--replicaof&#34;, &#34;leader&#34;, &#34;6379&#34;]

networks:
  local:
    driver: bridge

```

Running:

```bash
$ docker-compose up -d

```

Sets this up, and you can refer to the previous post for how to run some basic sanity checks on that

### Configuring Lettuce

_Be sure to check out the &#34;caveat&#34; section below if you planning on running the sample code locally._

To get lettuce to play ball, we can leverage spring qualifiers to pass in a different **RedisStringReactiveCommands** service into our data service.
The basic idea is that we will configure two different clients: one that connects to the primary for everything, and one that uses the read replicas. Here&#39;s the config class:

```java
@Configuration
public class RedisConfig {
    @Bean(&#34;redis-primary-commands&#34;)
    public RedisStringReactiveCommands&lt;String, String&gt; redisPrimaryReactiveCommands(RedisClient redisClient) {
        return redisClient.connect().reactive();
    }

    @Bean(&#34;redis-primary-client&#34;)
    public RedisClient redisClient(RedisPrimaryConfig redisPrimaryConfig) {
        return RedisClient.create(
                // adjust things like thread pool size with client resources
                ClientResources.builder().build(),
                &#34;redis://&#34; &#43; redisPrimaryConfig.getHost() &#43; &#34;:&#34; &#43; redisPrimaryConfig.getPort()
        );
    }

    @Bean(&#34;redis-replica-commands&#34;)
    public RedisStringReactiveCommands&lt;String, String&gt; redisReplicaReactiveCommands(RedisPrimaryConfig redisPrimaryConfig) {
        RedisURI redisPrimaryURI = RedisURI.builder()
                .withHost(redisPrimaryConfig.getHost())
                .withPort(redisPrimaryConfig.getPort())
                .build();

        RedisClient redisClient = RedisClient.create(
                redisPrimaryURI
        );

        StatefulRedisMasterReplicaConnection&lt;String, String&gt; primaryAndReplicaConnection = MasterReplica.connect(
                redisClient,
                StringCodec.UTF8,
                redisPrimaryURI
        );

        primaryAndReplicaConnection.setReadFrom(ReadFrom.REPLICA);

        return primaryAndReplicaConnection.reactive();
    }
}

```

With this, we can modify our service to use it properly like so:

```java
@Service
@Log4j2
public class RedisDataService {

    private final RedisStringReactiveCommands&lt;String, String&gt; redisPrimaryCommands;
    private RedisStringReactiveCommands&lt;String, String&gt; redisReplicaCommands;

    public RedisDataService(
            @Qualifier(&#34;redis-primary-commands&#34;) RedisStringReactiveCommands&lt;String, String&gt; redisPrimaryCommands,
            @Qualifier(&#34;redis-replica-commands&#34;) RedisStringReactiveCommands&lt;String, String&gt; redisReplicaCommands
    ) {
        this.redisPrimaryCommands = redisPrimaryCommands;
        this.redisReplicaCommands = redisReplicaCommands;
    }

    public Mono&lt;Void&gt; writeThing(Thing thing) {
        return this.redisPrimaryCommands
                .set(thing.getId().toString(), thing.getValue())
                .then();
    }

    public Mono&lt;Thing&gt; getThing(Integer id) {
        log.info(&#34;getting {} from replica&#34;, id);
        return this.redisReplicaCommands.get(id.toString())
                .map(response -&gt; Thing.builder().id(id).value(response).build());
    }

    public Mono&lt;Thing&gt; getThingPrimary(Integer id) {
        log.info(&#34;getting {} from primary&#34;, id);
        return this.redisPrimaryCommands.get(id.toString())
                .map(response -&gt; Thing.builder().id(id).value(response).build());
    }
}

```

Here, anytime you call **getThingPrimary**, it will use a client connection pool that only communicates with the primary node. When you call **getThing**, it will pick one of the replicas to execute the **get** command against.

Let&#39;s set up a controller to do some sanity testing that our configuration does what it&#39;s supposed to:

```java
@RestController
public class SampleController {
    private final RedisDataService redisDataService;

    public SampleController(RedisDataService redisDataService) {
        this.redisDataService = redisDataService;
    }

    @GetMapping(&#34;/redis/{key}&#34;)
    public Mono&lt;ResponseEntity&lt;Thing&gt;&gt; getRedisValue(@PathVariable(&#34;key&#34;) Integer key) {
        return redisDataService.getThing(key)
                .flatMap(thing -&gt; Mono.just(ResponseEntity.ok(thing)))
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @GetMapping(&#34;/primary-redis/{key}&#34;)
    public Mono&lt;ResponseEntity&lt;Thing&gt;&gt; getPrimaryRedisValue(@PathVariable(&#34;key&#34;) Integer key) {
        return redisDataService.getThingPrimary(key)
                .flatMap(thing -&gt; Mono.just(ResponseEntity.ok(thing)))
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }
}

```

One more thing we can do is add a package level debug log for lettuce, so we can inspect the output and see what commands are being executed where:

```yaml
redis-primary:
  host: 127.0.0.1
  port: 6379

logging.level.io.lettuce.core: DEBUG

```

When I start up the app locally, I can curl to invoke the endpoints:

```bash
$ redis-cli set 3 &#34;something&#34;
OK
$ curl localhost:8080/redis/3 | json_pp
{
   &#34;value&#34; : &#34;something&#34;,
   &#34;id&#34; : 3
}
$ curl localhost:8080/primary-redis/3 | json_pp
{
   &#34;id&#34; : 3,
   &#34;value&#34; : &#34;something&#34;
}

```

And with debug logging working as expected, I can see in the logs:

```bash
 INFO 19336 --- [or-http-epoll-1] c.n.r.service.RedisDataService           : getting 3 from replica
DEBUG 19336 --- [or-http-epoll-1] io.lettuce.core.RedisChannelHandler      : dispatching command SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
DEBUG 19336 --- [or-http-epoll-1] i.l.c.m.MasterReplicaConnectionProvider  : getConnectionAsync(READ)
DEBUG 19336 --- [or-http-epoll-1] io.lettuce.core.RedisChannelHandler      : dispatching command SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
DEBUG 19336 --- [or-http-epoll-1] i.lettuce.core.protocol.DefaultEndpoint  : [channel=0x049fafcf, /172.22.0.1:50614 -&gt; 172.22.0.3/172.22.0.3:6379, epid=0x5] write() writeAndFlush command SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
DEBUG 19336 --- [or-http-epoll-1] i.lettuce.core.protocol.DefaultEndpoint  : [channel=0x049fafcf, /172.22.0.1:50614 -&gt; 172.22.0.3/172.22.0.3:6379, epid=0x5] write() done
DEBUG 19336 --- [llEventLoop-8-4] io.lettuce.core.protocol.CommandHandler  : [channel=0x049fafcf, /172.22.0.1:50614 -&gt; 172.22.0.3/172.22.0.3:6379, epid=0x5, chid=0x5] write(ctx, SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command], promise)
DEBUG 19336 --- [llEventLoop-8-4] io.lettuce.core.protocol.CommandEncoder  : [channel=0x049fafcf, /172.22.0.1:50614 -&gt; 172.22.0.3/172.22.0.3:6379] writing command SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
DEBUG 19336 --- [llEventLoop-8-4] io.lettuce.core.protocol.CommandHandler  : [channel=0x049fafcf, /172.22.0.1:50614 -&gt; 172.22.0.3/172.22.0.3:6379, epid=0x5, chid=0x5] Received: 15 bytes, 1 commands in the stack
DEBUG 19336 --- [llEventLoop-8-4] io.lettuce.core.protocol.CommandHandler  : [channel=0x049fafcf, /172.22.0.1:50614 -&gt; 172.22.0.3/172.22.0.3:6379, epid=0x5, chid=0x5] Stack contains: 1 commands
DEBUG 19336 --- [llEventLoop-8-4] i.l.core.protocol.RedisStateMachine      : Decode done, empty stack: true
DEBUG 19336 --- [llEventLoop-8-4] io.lettuce.core.protocol.CommandHandler  : [channel=0x049fafcf, /172.22.0.1:50614 -&gt; 172.22.0.3/172.22.0.3:6379, epid=0x5, chid=0x5] Completing command SubscriptionCommand [type=GET, output=ValueOutput [output=something, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
 INFO 19336 --- [or-http-epoll-2] c.n.r.service.RedisDataService           : getting 3 from primary
DEBUG 19336 --- [or-http-epoll-2] io.lettuce.core.RedisChannelHandler      : dispatching command SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
DEBUG 19336 --- [or-http-epoll-2] i.lettuce.core.protocol.DefaultEndpoint  : [channel=0xaf43d87d, /127.0.0.1:41600 -&gt; 127.0.0.1/127.0.0.1:6379, epid=0x1] write() writeAndFlush command SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
DEBUG 19336 --- [or-http-epoll-2] i.lettuce.core.protocol.DefaultEndpoint  : [channel=0xaf43d87d, /127.0.0.1:41600 -&gt; 127.0.0.1/127.0.0.1:6379, epid=0x1] write() done
DEBUG 19336 --- [llEventLoop-5-1] io.lettuce.core.protocol.CommandHandler  : [channel=0xaf43d87d, /127.0.0.1:41600 -&gt; 127.0.0.1/127.0.0.1:6379, epid=0x1, chid=0x1] write(ctx, SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command], promise)
DEBUG 19336 --- [llEventLoop-5-1] io.lettuce.core.protocol.CommandEncoder  : [channel=0xaf43d87d, /127.0.0.1:41600 -&gt; 127.0.0.1/127.0.0.1:6379] writing command SubscriptionCommand [type=GET, output=ValueOutput [output=null, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]
DEBUG 19336 --- [llEventLoop-5-1] io.lettuce.core.protocol.CommandHandler  : [channel=0xaf43d87d, /127.0.0.1:41600 -&gt; 127.0.0.1/127.0.0.1:6379, epid=0x1, chid=0x1] Received: 15 bytes, 1 commands in the stack
DEBUG 19336 --- [llEventLoop-5-1] io.lettuce.core.protocol.CommandHandler  : [channel=0xaf43d87d, /127.0.0.1:41600 -&gt; 127.0.0.1/127.0.0.1:6379, epid=0x1, chid=0x1] Stack contains: 1 commands
DEBUG 19336 --- [llEventLoop-5-1] i.l.core.protocol.RedisStateMachine      : Decode done, empty stack: true
DEBUG 19336 --- [llEventLoop-5-1] io.lettuce.core.protocol.CommandHandler  : [channel=0xaf43d87d, /127.0.0.1:41600 -&gt; 127.0.0.1/127.0.0.1:6379, epid=0x1, chid=0x1] Completing command SubscriptionCommand [type=GET, output=ValueOutput [output=something, error=&#39;null&#39;], commandType=io.lettuce.core.protocol.Command]

```

Digging in there, you can see that when we hit the replica, we are connecting to the ip address **172.22.0.3** and when we hit the primary, we are connecting to **127.0.0.1** \[the value in our config, loopback\]. Which is the desired behavior.

### An Important Caveat for Local

There&#39;s an important note for what follows here: because I&#39;m running these tests on a computer running Linux, I can actually access the containers running by their bridge IP address. Therefore, if the IP address for a redis node inside the docker network is **127.22.0.2**, I can actually run this redis-cli command and it works:

```bash
$ redis-cli -p 6379 -h 172.22.0.2 info
...bunch of stuff...
# Replication
role:master
connected_slaves:1
slave0:ip=172.22.0.3,port=6379,state=online,offset=2828,lag=0
...

```

**You can&#39;t do this on mac** \[or, I&#39;m pretty sure, Windows\].

Because lettuce is getting the replica IP address from the primary \[by running INFO, as I did here\], starting up this example on a non-Linux box won&#39;t &#34;just work&#34; as long as the application is running on your host machine, and not in the docker compose network. You will likely have to create a special configuration for local only to get around this issue for now, but this will work in a &#34;real&#34; environment or if you configure redis in a non-docker environment.

Do remember to [check out the sample code on Github](https://github.com/nfisher23/reactive-programming-webflux), which even if you&#39;re developing on a non Linux box should be a good place to start for higher environments
