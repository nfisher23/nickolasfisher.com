---
title: "Pre Loading a Lua Script into Redis With Lettuce"
date: 2021-04-01T00:00:00
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

In my last article on [running a lua script against redis with lettuce](https://nickolasfisher.com/blog/How-to-Run-a-Lua-Script-against-Redis-using-Lettuce), we just sent the entire script \[that redis will execute atomically\] along with the arguments every time. For very small scripts this is unlikely to be a problem, but there is definitely a more efficient way to do this, using [EVALSHA](https://redis.io/commands/evalsha).

### How EVALSHA Works

Running a lua script without evalsha means that we send the script and the arguments every time, like we have covered already:

``` bash
redis-cli eval &#34;return redis.call(&#39;set&#39;,KEYS[1],ARGV[1],&#39;ex&#39;,ARGV[2])&#34; 1 foo1 bar1 10
OK

```

**SCRIPT LOAD** allows us to tell redis &#34;this is my script, please remember it&#34;, then we can use EVALSHA to run the script that redis now remembers. For example, using the CLI:

``` bash
redis-cli
&gt; SCRIPT LOAD &#34;return redis.call(&#39;set&#39;,KEYS[1],ARGV[1],&#39;ex&#39;,ARGV[2])&#34;
&#34;cf4df3d8eb7f521ceb285c6870e5713d79e2bb0b&#34;
&gt; evalsha cf4df3d8eb7f521ceb285c6870e5713d79e2bb0b 1 foo1 bar1 10
OK

```

We can verify that works with a shell script like:

``` bash
$ SHA=$(redis-cli script load &#34;return redis.call(&#39;set&#39;,KEYS[1],ARGV[1],&#39;ex&#39;,ARGV[2])&#34;)
$ redis-cli evalsha &#34;$SHA&#34; 1 foo1 bar1 10; redis-cli ttl foo1; redis-cli get foo1
OK
(integer) 10
&#34;bar1&#34;

```

By referencing the hash of the script \[sha1 hash, to be more specific\], we don&#39;t have to send the entire script. Indeed, regardless of how big a script we load, the size of the hash that represents the script will stay compact.

### EVALSHA with Lettuce

EVALSHA with lettuce can work much the same way, if we want it to. Just load the script and used the returned hash \[note that the SHA1 hash is represented as a hexadecimal string\]:

``` java
    @Test
    public void scriptLoadFromResponse() {
        String shaOfScript = redisReactiveCommands.scriptLoad(SAMPLE_LUA_SCRIPT).block();

        StepVerifier.create(redisReactiveCommands.evalsha(
                shaOfScript,
                ScriptOutputType.BOOLEAN,
                // keys as an array
                Arrays.asList(&#34;foo1&#34;).toArray(new String[0]),
                // other arguments
                &#34;bar1&#34;, &#34;10&#34;)
        )
                .expectNext(true)
                .verifyComplete();
    }

```

If you want to generate the hash of the script yourself, there are several libraries available to you. Just get the SHA1 hash of the script \[assuming UTF-8 encoding, which java strings are\], then encode the output into a hex string. We can see that the response from redis and our code generate the same sha:

``` java
    @Test
    public void scriptLoadFromDigest() throws Exception {
        MessageDigest md = MessageDigest.getInstance(&#34;SHA-1&#34;);
        byte[] digestAsBytes = md.digest(SAMPLE_LUA_SCRIPT.getBytes(StandardCharsets.UTF_8));
        String hexadecimalStringOfScriptSha1 = Hex.encodeHexString(digestAsBytes);
        String hexStringFromRedis = redisReactiveCommands.scriptLoad(SAMPLE_LUA_SCRIPT).block();

        // they&#39;re the same
        assertEquals(hexadecimalStringOfScriptSha1, hexStringFromRedis);

        StepVerifier.create(redisReactiveCommands.evalsha(
                hexadecimalStringOfScriptSha1,
                ScriptOutputType.BOOLEAN,
                // keys as an array
                Arrays.asList(&#34;foo1&#34;).toArray(new String[0]),
                // other arguments
                &#34;bar1&#34;, &#34;10&#34;)
        )
                .expectNext(true)
                .verifyComplete();
    }

```

Note that I&#39;m using an apache commons library to take the byte array and encode it to hex in this case. The internet has [several suggestions for how you can encode a byte array to a hex string yourself](https://stackoverflow.com/questions/9655181/how-to-convert-a-byte-array-to-a-hex-string-in-java) if you don&#39;t like the way I&#39;ve done it here.

Remember that the primary benefit here is that you don&#39;t have to send the script over the wire and have redis decode it every single time, which can be significant if used frequently.


