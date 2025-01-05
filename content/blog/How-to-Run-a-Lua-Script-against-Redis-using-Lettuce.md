---
title: "How to Run a Lua Script against Redis using Lettuce"
date: 2021-04-24T16:55:51
draft: false
tags: [java, spring, webflux, lettuce, redis]
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Running a lua script against redis is done using [EVAL](https://redis.io/commands/eval). The primary benefit of using a lua script is that the entire script is guaranteed to be run at once, and nothing else will interfere with it \[it's atomic\]. This allows for operating on multiple keys, or check-then-set type operations on the same key.

Executing a script using the redis cli looks like this:

```bash
> EVAL "return redis.call('set',KEYS[1],ARGV[1],'ex',ARGV[2])" 1 foo1 bar1 10
OK

```

This script is simple \[and we don't need a script for this, it's just used as an example\], it just calls redis and tells it to set the key **foo1** to value **bar1** with a time to live of 10 seconds.

We can verify that script works in our shell with something like:

```bash
$ redis-cli eval "return redis.call('set',KEYS[1],ARGV[1],'ex',ARGV[2])" 1 foo1 bar1 10; redis-cli ttl foo1; redis-cli get foo1
OK
(integer) 10
"bar1"

```

### Lua Scripting with Lettuce

For a fast feedback loop, you can refer to either using [embedded redis to test lettuce](https://nickolasfisher.com/blog/how-to-use-embedded-redis-to-test-a-lettuce-client-in-spring-boot-webflux) or [using a redis test container to test lettuce](https://nickolasfisher.com/blog/how-to-use-a-redis-test-container-with-lettucespring-boot-webflux) as a starting point. Once we have that, testing the same lua script with lettuce can look something like this:

```java
    public static final String SAMPLE_LUA_SCRIPT = "return redis.call('set',KEYS[1],ARGV[1],'ex',ARGV[2])";

    @Test
    public void executeLuaScript() {
        String script = SAMPLE_LUA_SCRIPT;

        StepVerifier.create(redisReactiveCommands.eval(script, ScriptOutputType.BOOLEAN,
                // keys as an array
                Arrays.asList("foo1").toArray(new String[0]),
                // other arguments
                "bar1", "10"
                )
        )
                .expectNext(true)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.get("foo1"))
                .expectNext("bar1")
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.ttl("foo1"))
                .expectNextMatches(ttl -> 7 < ttl &amp;&amp; 11 > ttl)
                .verifyComplete();
    }

```

This code uses the same lua script that we used in the cli in the example before this to redis along with arguments. The third argument in our **eval** command is the keys, the fourth are arbitrary arguments

This should get you started, and from here I would recommend you read through the [eval section in the redis docs](https://redis.io/commands/eval) as well as read my next post about [speeding up lua script execution by loading](https://nickolasfisher.com/blog/pre-loading-a-lua-script-into-redis-with-lettuce) the script into the redis cache and referencing it, rather than re-sending it over the wire each time.
