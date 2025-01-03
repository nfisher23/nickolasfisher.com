---
title: "How to Configure Lettuce to connect to a local Redis Instance with Webflux"
date: 2021-03-28T17:49:16
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/reactive-redis).

In a previous post, we detailed [how to write integration tests for lettuce clients in spring boot webflux](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux) using a redis test container. That&#39;s fine and well when you&#39;re just writing code for a quick feedback loop, but is useless when it comes to running the application in real life. This post will start up redis locally and then explain how to best connect to it using lettuce in webflux.

We will build off of code from that previous blog post. If you&#39;ll recall, we had a service like so:

```java
@Service
public class RedisDataService {

    private final RedisStringReactiveCommands&lt;String, String&gt; redisStringReactiveCommands;

    public RedisDataService(RedisStringReactiveCommands&lt;String, String&gt; redisStringReactiveCommands) {
        this.redisStringReactiveCommands = redisStringReactiveCommands;
    }

    public Mono&lt;Void&gt; writeThing(Thing thing) {
        return this.redisStringReactiveCommands
                .set(thing.getId().toString(), thing.getValue())
                .then();
    }

    public Mono&lt;Thing&gt; getThing(Integer id) {
        return this.redisStringReactiveCommands.get(id.toString())
                .map(response -&gt; Thing.builder().id(id).value(response).build());
    }
}

```

The current problem here is that there is no **RedisStringReactiveCommands** bean available as of now, we don&#39;t have any redis client set up under the hood.

To do so is fairly straightforward. Let&#39;s start by creating a configuration class that contains the necessary host, port, and beans:

```java
@Configuration
@ConfigurationProperties(prefix = &#34;lettuce&#34;)
public class RedisConfig {

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

    @Bean
    public RedisStringReactiveCommands&lt;String, String&gt; getRedis(RedisClient redisClient) {
        return redisClient.connect().reactive();
    }

    @Bean
    public RedisClient redisClient() {
        return RedisClient.create(
                // adjust things like thread pool size with client resources
                ClientResources.builder().build(),
                &#34;redis://&#34; &#43; this.getHost() &#43; &#34;:&#34; &#43; this.getPort()
        );
    }
}

```

With this in place, we can now change our **application.yaml** configuration file to contain the host and port we&#39;re looking for. Since we&#39;re going to stand up a local redis instance, we&#39;ll use the loopback and a standard redis port:

```yaml
lettuce:
  host: 127.0.0.1
  port: 6379

```

Now let&#39;s run a quick manual verification of our setup. I&#39;m first going to create a controller class that leverages our data service and just returns what&#39;s in redis for that integer key:

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
}

```

And I&#39;ll setup a **docker-compose.yaml** to provision my local redis:

```yaml
#version: &#34;3.3&#34;
services:
  redis:
    image: &#34;redis:alpine&#34;
    ports:
      - &#34;6379:6379&#34;

```

If you hop to the directory where that docker compose file is defined, then run:

```bash
$ docker-compose up

```

Then you can start up your service.

A quick test that everything is working properly could be:

```bash
$ redis-cli set 3 &#34;something&#34;
OK
$ curl localhost:8080/redis/3 | json_pp
{
   &#34;value&#34; : &#34;something&#34;,
   &#34;id&#34; : 3
}

```

And you should be good to go
