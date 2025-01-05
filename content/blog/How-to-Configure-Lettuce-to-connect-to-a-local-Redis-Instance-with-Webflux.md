---
title: "How to Configure Lettuce to connect to a local Redis Instance with Webflux"
date: 2021-03-28T17:49:16
draft: false
tags: [java, spring, webflux, lettuce, redis]
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/reactive-redis).

In a previous post, we detailed [how to write integration tests for lettuce clients in spring boot webflux](https://nickolasfisher.com/blog/how-to-use-a-redis-test-container-with-lettucespring-boot-webflux) using a redis test container. That's fine and well when you're just writing code for a quick feedback loop, but is useless when it comes to running the application in real life. This post will start up redis locally and then explain how to best connect to it using lettuce in webflux.

We will build off of code from that previous blog post. If you'll recall, we had a service like so:

```java
@Service
public class RedisDataService {

    private final RedisStringReactiveCommands<String, String> redisStringReactiveCommands;

    public RedisDataService(RedisStringReactiveCommands<String, String> redisStringReactiveCommands) {
        this.redisStringReactiveCommands = redisStringReactiveCommands;
    }

    public Mono<Void> writeThing(Thing thing) {
        return this.redisStringReactiveCommands
                .set(thing.getId().toString(), thing.getValue())
                .then();
    }

    public Mono<Thing> getThing(Integer id) {
        return this.redisStringReactiveCommands.get(id.toString())
                .map(response -> Thing.builder().id(id).value(response).build());
    }
}

```

The current problem here is that there is no **RedisStringReactiveCommands** bean available as of now, we don't have any redis client set up under the hood.

To do so is fairly straightforward. Let's start by creating a configuration class that contains the necessary host, port, and beans:

```java
@Configuration
@ConfigurationProperties(prefix = "lettuce")
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
    public RedisStringReactiveCommands<String, String> getRedis(RedisClient redisClient) {
        return redisClient.connect().reactive();
    }

    @Bean
    public RedisClient redisClient() {
        return RedisClient.create(
                // adjust things like thread pool size with client resources
                ClientResources.builder().build(),
                "redis://" + this.getHost() + ":" + this.getPort()
        );
    }
}

```

With this in place, we can now change our **application.yaml** configuration file to contain the host and port we're looking for. Since we're going to stand up a local redis instance, we'll use the loopback and a standard redis port:

```yaml
lettuce:
  host: 127.0.0.1
  port: 6379

```

Now let's run a quick manual verification of our setup. I'm first going to create a controller class that leverages our data service and just returns what's in redis for that integer key:

```java
@RestController
public class SampleController {
    private final RedisDataService redisDataService;

    public SampleController(RedisDataService redisDataService) {
        this.redisDataService = redisDataService;
    }

    @GetMapping("/redis/{key}")
    public Mono<ResponseEntity<Thing>> getRedisValue(@PathVariable("key") Integer key) {
        return redisDataService.getThing(key)
                .flatMap(thing -> Mono.just(ResponseEntity.ok(thing)))
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }
}

```

And I'll setup a **docker-compose.yaml** to provision my local redis:

```yaml
#version: "3.3"
services:
  redis:
    image: "redis:alpine"
    ports:
      - "6379:6379"

```

If you hop to the directory where that docker compose file is defined, then run:

```bash
$ docker-compose up

```

Then you can start up your service.

A quick test that everything is working properly could be:

```bash
$ redis-cli set 3 "something"
OK
$ curl localhost:8080/redis/3 | json_pp
{
   "value" : "something",
   "id" : 3
}

```

And you should be good to go
