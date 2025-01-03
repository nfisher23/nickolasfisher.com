---
title: "How to Create an Embedded PostgreSQL Database With Spring Boot"
date: 2019-04-20T15:28:25
draft: false
tags: [java, spring, DevOps, postgreSQL]
---

You can see the sample code for this post [on GitHub](https://github.com/nfisher23/postgres-flyway-example).

[PostgreSQL](https://www.postgresql.org/) is still my favorite database, and if a project I'm working on makes sense as a relational database model, it's always what I reach for.

Automating database tests, and maintaining consistency between environments, is one of the biggest pain points between working locally and deploying to higher environments. In particular, when you need to take advantage of native features of the database you're using (since consistency between vendors on some of the finer details is nearly a pipe-dream at this point), using a general in memory database (like H2) just doesn't cut it.

To start using a PostgreSQL in memory database (with _as little_ spring boot magic as possible), you will first need to ensure that you have a PostgreSQL dependency. If you're using Maven, that's:

```xml
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>
```

We can then resort to using [opentable](https://github.com/opentable/otj-pg-embedded) as the in memory engine by adding another dependency:

```xml
<dependency>
    <groupId>com.opentable.components</groupId>
    <artifactId>otj-pg-embedded</artifactId>
    <version>0.13.1</version>
    <scope>compile</scope>
</dependency>
```

Finally, wherever we want the embedded database, we can spin it up with default settings like:

```java
package com.nickolasfisher.flywaystuff;

... imports ...

@Configuration
@ComponentScan
@Profile("dev")
public class DevConfig {

    @Bean
    @Primary
    public DataSource inMemoryDS() throws Exception {
        DataSource embeddedPostgresDS = EmbeddedPostgres.builder()
                .start().getPostgresDatabase();

        return embeddedPostgresDS;
    }
}

```

Next up, we'll look at using [Flyway](https://flywaydb.org/) to run idempotent database migration scripts against our database on application startup, giving the application flexible and full control over the state of the schemas it owns.
