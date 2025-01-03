---
title: "Working with String Types in Redis using Lettuce and Webflux"
date: 2021-04-01T00:00:00
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

There are, as of this writing, [27 different string operations available in the redis API](https://redis.io/commands/#string). Lettuce appears to have interfaces that directly support all of them.

This article will walk you through some of the more common commands and how to use them against a redis instance.

### Setting up the Test Suite

We&#39;re going to build off of previous work where we [set up a redis test container to test lettuce](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux), and assuming you have cloned that project and are following along with the right dependencies, I will make a new test class that for now just creates the test container, configured a redis client against that container, and flushes \[removes in redis lingo\] all the data from redis after each test method runs:

``` java
@Testcontainers
public class StringTypesTest {

    @Container
    public static GenericContainer genericContainer = new GenericContainer(
            DockerImageName.parse(&#34;redis:5.0.3-alpine&#34;)
    ).withExposedPorts(6379);

    private RedisClient redisClient;

    @BeforeEach
    public void setupRedisClient() {
        redisClient = RedisClient.create(&#34;redis://&#34; &#43; genericContainer.getHost() &#43; &#34;:&#34; &#43; genericContainer.getMappedPort(6379));
    }

    @AfterEach
    public void removeAllDataFromRedis() {
        redisClient.connect().reactive().flushall().block();
    }
}

```

With this in place, we can begin hacking away.

### Set, Get, and Additional Arguments

This is straightforward:

``` java
    @Test
    public void setAndGet() {
        RedisReactiveCommands&lt;String, String&gt; redisReactiveCommands = redisClient.connect().reactive();

        // vanilla get and set
        StepVerifier.create(redisReactiveCommands.set(&#34;some-key-1&#34;, &#34;some-value-1&#34;))
                .expectNextMatches(response -&gt; &#34;OK&#34;.equals(response)).verifyComplete();

        StepVerifier.create(redisReactiveCommands.get(&#34;some-key-1&#34;))
                .expectNextMatches(response -&gt; &#34;some-value-1&#34;.equals(response))
                .verifyComplete();

        // adding an additional argument like nx will cause it to return nothing if it doesn&#39;t get set
        StepVerifier.create(redisReactiveCommands.set(&#34;some-key-1&#34;, &#34;some-value-2&#34;, new SetArgs().nx()))
                .verifyComplete();

        // prove the value is the same
        StepVerifier.create(redisReactiveCommands.get(&#34;some-key-1&#34;))
                .expectNextMatches(response -&gt; &#34;some-value-1&#34;.equals(response))
                .verifyComplete();
    }

```

We set **some-key-1** to have **some-value-1**, and verify it&#39;s there. We then use the NX argument, which only sets the value if it doesn&#39;t exist. We then verify that, because the key was just set, it is not overwritten, by getting it again and asserting the value

### Set NX and Set EX

If we don&#39;t like that interface of adding an additional argument for set nx, set ex, etc., then lettuce does provide a slightly more intuitive interface:

``` java
    @Test
    public void setNx() throws Exception {
        RedisReactiveCommands&lt;String, String&gt; redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.setnx(&#34;key-1&#34;, &#34;value-1&#34;))
                .expectNextMatches(success -&gt; success)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.setnx(&#34;key-1&#34;, &#34;value-2&#34;))
                .expectNextMatches(success -&gt; !success)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.setex(&#34;key-1&#34;, 1, &#34;value-1&#34;))
                .expectNextMatches(response -&gt; &#34;OK&#34;.equals(response))
                .verifyComplete();

        // key-1 expires in 1 second
        Thread.sleep(1500);

        StepVerifier.create(redisReactiveCommands.get(&#34;key-1&#34;))
                // no value
                .verifyComplete();
    }

```

We show that trying to set a value that already exists with the nx option fails, and that setting a value with the ex option will indeed expire it within the specified period of time.

### Append

**append** will append a string to an existing string, then return the length of the existing string:

``` java
    @Test
    public void append() {
        RedisReactiveCommands&lt;String, String&gt; redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.set(&#34;key-10&#34;, &#34;value-10&#34;))
                .expectNextMatches(response -&gt; &#34;OK&#34;.equals(response))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.append(&#34;key-10&#34;, &#34;-more-stuff&#34;))
                // length of new value is returned
                .expectNextMatches(response -&gt; 19L == response)
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.get(&#34;key-10&#34;))
                .expectNextMatches(response -&gt;
                        &#34;value-10-more-stuff&#34;.equals(response))
                .verifyComplete();
    }

```

We set a key to work with, then append **-more-stuff** to the value, then assert that we get the right length returned and finally make sure the new value looks correct.

### IncrBy

**incrby** increments the value associated with that key by the specified amount. So if the value is 7 and we **incrby** 8, we should get 15:

``` java
    @Test
    public void incrBy() {
        RedisReactiveCommands&lt;String, String&gt; redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.set(&#34;key-counter&#34;, &#34;7&#34;))
                .expectNextMatches(response -&gt; &#34;OK&#34;.equals(response))
                .verifyComplete();

        StepVerifier.create(redisReactiveCommands.incrby(&#34;key-counter&#34;, 8L))
                .expectNextMatches(val -&gt; 15 == val)
                .verifyComplete();
    }

```

Here, we assert exactly that, 7 &#43; 8 is indeed 15 and it is returned to us by redis.

### MGET and MSET

**mset** and **mget** are just the multiples version of **get** and **set**. If we **mset** then we are setting multiple keys at once. If we **mget** then we are getting multiple values from the keys at once:

``` java
    @Test
    public void mget() {
        RedisReactiveCommands&lt;String, String&gt; redisReactiveCommands = redisClient.connect().reactive();

        StepVerifier.create(redisReactiveCommands.mset(Map.of(
                &#34;key-1&#34;, &#34;val-1&#34;,
                &#34;key-2&#34;, &#34;val-2&#34;,
                &#34;key-3&#34;, &#34;val-3&#34;
        )))
                .expectNextMatches(response -&gt; &#34;OK&#34;.equals(response))
                .verifyComplete();

        Flux&lt;KeyValue&lt;String, String&gt;&gt; mgetValuesFlux = redisReactiveCommands.mget(&#34;key-1&#34;, &#34;key-2&#34;, &#34;key-3&#34;);
        StepVerifier.create(mgetValuesFlux.collectList())
                .expectNextMatches(collectedValues -&gt;
                        collectedValues.size() == 3
                            &amp;&amp; collectedValues.stream()
                                .anyMatch(stringStringKeyValue -&gt;
                                        stringStringKeyValue.getKey().equals(&#34;key-1&#34;)
                                                &amp;&amp; stringStringKeyValue.getValue().equals(&#34;val-1&#34;)
                                )
                )
                .verifyComplete();
    }

```

We set three keys and values in the same command using **mset**, then use **mget** to assert that we do in fact get three keys and values in response. The interface returns a flux, so to simplify it we just collect the flux into a mono containing a list of all the emitted items.

You can feel free to explore the previously linked other string commands that redis exposes via its API, but this should be a good start.


