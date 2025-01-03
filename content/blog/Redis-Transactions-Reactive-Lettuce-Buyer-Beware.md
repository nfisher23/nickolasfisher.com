---
title: "Redis Transactions, Reactive Lettuce: Buyer Beware"
date: 2021-04-01T00:00:00
draft: false
---

The source code for what follows [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux).

Redis Transactions do not operate exactly the way you would expect if you&#39;re coming from a relational database management system like MySQL or postrgres. It&#39;s mostly useful for optimistic locking, but honestly there are better ways to accomplish many of the things you&#39;re probably trying to, like [running a lua script with arguments](https://nickolasfisher.com/blog/How-to-Run-a-Lua-Script-against-Redis-using-Lettuce) \[which is guaranteed to be atomic\]. The [documentation on transactions in redis](https://redis.io/topics/transactions) describes some of the caveats, the biggest one probably being that it does not support rollbacks, only commits or discards.

In general, I think there are better ways to do things in redis \[especially if you&#39;re using the reactive lettuce client, as we will see\] but presumably you have a use case for it which is why you&#39;re here.

It will be easier to follow along with what follows if you have either [set up embedded redis for lettuce testing](https://nickolasfisher.com/blog/How-to-use-Embedded-Redis-to-Test-a-Lettuce-Client-in-Spring-Boot-Webflux) or [set up a test container for lettuce testing](https://nickolasfisher.com/blog/How-to-use-a-Redis-Test-Container-with-LettuceSpring-Boot-Webflux).

### Transactions and Lettuce

The first thing you&#39;ll need to take note of is that you don&#39;t get transactions for free with the reactive client. To be more specific, [the lettuce documentation on transactions states](https://github.com/lettuce-io/lettuce-core/wiki/Transactions) that **&#34;Lettuce itself does not synchronize transactional/non-transactional invocations regardless of the used API facade&#34;**. In practice, this usually means you&#39;ll have to be very careful to ensure that each transaction has its own dedicated connection, and if you&#39;re reusing connections across multiple threads \[as is the default with reactive programming\] you&#39;re going to have a bad time.

Once we do have a dedicated connection, we can start a transaction using **MULTI**:

``` java
    @Test
    public void transactions() throws InterruptedException {
        RedisReactiveCommands&lt;String, String&gt; firstConnection =
                redisClient.connect().reactive();

        RedisReactiveCommands&lt;String, String&gt; secondConnection =
                redisClient.connect().reactive();

        StepVerifier.create(firstConnection.multi())
                .expectNext(&#34;OK&#34;)
                .verifyComplete();

        ....
    }

```

Here is where things get weird. The way transactions work in redis is that each command gets queued \[by responding with QUEUED\], and once you commit \[EXEC\], then all the queued commands get executed at once. The way that works with the CLI looks like this:

``` bash
$ redis-cli
127.0.0.1:6379&gt; MULTI
OK
127.0.0.1:6379&gt; set key1 foo1 EX 5
QUEUED
127.0.0.1:6379&gt; EXEC
1) OK

```

So the CLI will actually respond to your commands with QUEUED and you can be confident that it was acknowledged and actually queued by redis.

Not so with lettuce. If we, at this point, try to run code like so:

``` java
        StepVerifier.create(firstConnection.set(&#34;key-1&#34;, &#34;value-1&#34;))
                .expectNext(&#34;OK&#34;)
                .verifyComplete();

```

Then our code will spin and spin and not complete naturally, so we don&#39;t get confirmation that our command was sent and acknowledged by redis. That&#39;s because the lettuce client _won&#39;t call onNext or onComplete until the transaction actually commits_. We can demonstrated this by modifying our test to look like:

``` java
    @Test
    public void transactions() throws InterruptedException {
        RedisReactiveCommands&lt;String, String&gt; firstConnection =
                redisClient.connect().reactive();

        RedisReactiveCommands&lt;String, String&gt; secondConnection =
                redisClient.connect().reactive();

        StepVerifier.create(firstConnection.multi())
                .expectNext(&#34;OK&#34;)
                .verifyComplete();

        firstConnection.set(&#34;key-1&#34;, &#34;value-1&#34;)
            .subscribe(resp -&gt;
                System.out.println(
                    &#34;response from set within transaction: &#34; &#43; resp
                )
            );

        // no records yet, transaction not committed
        StepVerifier.create(secondConnection.get(&#34;key-1&#34;))
                .verifyComplete();

        Thread.sleep(20);
        System.out.println(&#34;running exec&#34;);
        StepVerifier.create(firstConnection.exec())
                .expectNextMatches(tr -&gt; {
                    System.out.println(&#34;exec responded&#34;);
                    return tr.size() == 1 &amp;&amp; tr.get(0).equals(&#34;OK&#34;);
                })
                .verifyComplete();

        StepVerifier.create(secondConnection.get(&#34;key-1&#34;))
                .expectNext(&#34;value-1&#34;)
                .verifyComplete();
    }

```

While this test passes, which does tell us that transactions &#34;work&#34; in the sense that nothing actually happens until EXEC is run, the printed output from the test tells the real story:

``` bash
running exec
response from set within transaction: OK
exec responded

```

That is, we don&#39;t get our response from setting the transaction until after EXEC has been sent to the server. This is personally not behavior that I&#39;m fond of, because we lose the backpressure associated with getting a reply and acting on that reply. Between this and the sketchy implementation of redis transactions, I would recommend you leave reactive transactions using lettuce in redis out of your toolbox and find a different way to solve your problem.


