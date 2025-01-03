---
title: "Bootstrap a Local Sharded Redis Cluster in Five Minutes"
date: 2021-04-10T18:24:12
draft: false
tags: []
---

If you're interested in understanding details of how clustered redis works \[that is to say, if you're more or less responsible for operationalizing it\], there is an excellent [section in the redis documentation](https://redis.io/topics/cluster-tutorial) that goes into some detail on it. I would advise everyone to read that at some point, but if you just want to get started hacking this is the TLDR; article that you're looking for. We will run through some basic commands to get up and running, and you can use this cluster to help figure out the details later on.

First you need to download redis source and build some binaries:

```bash
wget https://download.redis.io/releases/redis-6.2.1.tar.gz
tar xzf redis-6.2.1.tar.gz
cd redis-6.2.1
make

```

Building the project took a few minutes on my machine, so get yourself a cup of coffee.

It's done? You're back? Cool. Now it's time to create the cluster by starting some redis servers and joining them in the cluster together. There is a script that comes with the tarball you just downloaded that makes that pretty simple:

```bash
cd utils/create-cluster
./create-cluster start # starts the servers
./create-cluster create # joins them together in a cluster

```

Now you've got a locally running clustered redis. The output that you really want to pay attention to from running that last command is similar to:

```bash
Adding replica 127.0.0.1:30005 to 127.0.0.1:30001
Adding replica 127.0.0.1:30006 to 127.0.0.1:30002
Adding replica 127.0.0.1:30004 to 127.0.0.1:30003

```

Take any **non-replica** port from that output \[the second host/port combo, not the first\], then we'll connect to the cluster with our cli tool:

```bash
redis-cli -c -p 30001

```

Importantly, you will want to pass the **-c** argument to the cli startup so that it operates in clustered redis mode. Now let's issue some commands to prove that this is indeed clustered redis:

```bash
127.0.0.1:30001> SET 'wat' 2
-> Redirected to slot [7056] located at 127.0.0.1:30002
OK

```

The redirect is a good sign, the node we tried to write to corrected us on which node the write request actually needed to get to.

As you can see, the hash slot for the key **wat** was on a different node, so we were redirected to write to that node. We can further prove that we're in clustered redis by trying to issue a multi-set command without "telling" redis to put them all in the same hash slot by using hash tags \[detailed in [this more advanced article on clustered redis](https://redis.io/topics/cluster-spec)\], like so:

```bash
127.0.0.1:30002> MSET 'one' 1 'two' 2 'three' 3
(error) CROSSSLOT Keys in request don't hash to the same slot

```

This is a good sign--the multi write request was outright rejected because it didn't have three keys that were all assigned to the same primary node in the cluster. We need to use a hash tag to tell redis to use the same node:

```bash
127.0.0.1:30002> MSET '{first}one' 1 '{first}two' 2 '{first}three' 3
-> Redirected to slot [11149] located at 127.0.0.1:30003
OK

```

Now we can get all of those values with those keys, as a sanity check:

```bash
127.0.0.1:30003> MGET '{first}one' '{first}two' '{first}three'
1) "1"
2) "2"
3) "3"

```

And with that, you should be up and running.
