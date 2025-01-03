---
title: "Set up a Basic Leader/Follower Redis Cluster Locally using Docker"
date: 2021-03-28T18:57:07
draft: false
tags: [DevOps, redis]
---

In general, you will want to keep your development environment and your higher environments as similar as makes sense \[times it doesn't make sense: when it costs too much\], to catch bugs early and often. Here, we'll quickly run through how to set up a leader/follower topology for redis using docker/docker-compose on your local machine.

The [redis documentation on replication](https://redis.io/topics/replication) is a very good read to get more familiar with the details, but you basically just need to pass a flag/config value to the follower to tell it to start replicating. This will also, by default, make the replica reject all write requests \[you want this--trust me\]. Here's a docker-compose file that does just that:

```yaml
version: '3.8'

services:
  leader:
    image: redis
    ports:
      - "6379:6379"
      - 6379
    networks:
      - local
  follower:
    image: redis
    ports:
      - "6380:6379"
      - 6379
    networks:
      - local
    command: ["--replicaof", "leader", "6379"]

networks:
  local:
    driver: bridge

```

You can, somewhat obviously, start this up like:

```bash
$ docker-compose up -d

```

We can then test this with the cli like so:

```bash
$ redis-cli set 3 "something"
OK
$ redis-cli -p 6380 set 3 "something" # fails because you're trying to write to the replica
(error) READONLY You can't write against a read only replica.
$ redis-cli -p 6380 get 3 # get from replica, same value
"something"

```

If you're running a redis leader/follower topology in your staging/production environments or if you just want to experiment with how that might affect your application, this is probably the best place to start.
