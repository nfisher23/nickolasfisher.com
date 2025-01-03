---
title: "How to run a SQL Script Against a Postgres Database Using Ansible"
date: 2019-02-01T00:00:00
draft: false
---

The source code for this post can be found [on GitHub](https://github.com/nfisher23/run-sql-ansible-postgres).

Managing a live database, and in particular dealing with database migrations without allowing for any downtime in your application, is typically the most challenging part of any automated deployment strategy. Services can be spun up and down with impunity because their state at the beginning and at the end are exactly the same, but databases store data--their state is always changing.

From where I sit, there are two good options for dealing with database migrations: at an application level (e.g. a startup script when you connect with a service) or using a tool like Ansible. Either one of them allow you to write automation for the migrations, which is (in my opinion) non-negotiable for maintaining any non-trivial software project. While I lean towards the application owning the migrations, Ansible or another idempotent management tool is a somewhat close second, and may be better for your use case.

There are a few different ways to run a SQL script against Postgres using Ansible. The first is to take a sql file and dump it on the server you&#39;re managing, then run the sql script using a psql command. First we&#39;ll install Postgres for a Debian distribution with apt:

``` yaml
---
