---
title: "How to Create an Embedded PostgreSQL Database With Spring Boot"
date: 2019-04-01T00:00:00
draft: false
---

You can see the sample code for this post [on GitHub](https://github.com/nfisher23/postgres-flyway-example).

[PostgreSQL](https://www.postgresql.org/) is still my favorite database, and if a project I&#39;m working on makes sense as a relational database model, it&#39;s always what I reach for.

Automating database tests, and maintaining consistency between environments, is one of the biggest pain points between working locally and deploying to higher environments. In particular, when you need to take advantage of native features of the database you&#39;re using (since consistency between vendors on some of the finer details is nearly a pipe-dream at this point), using a general in memory database (like H2) just doesn&#39;t cut it.

To start using a PostgreSQL in memory database (with _as little_ spring boot magic as possible), you will first need to ensure that you have a PostgreSQL dependency. If you&#39;re using Maven, that&#39;s:

``` xml
&lt;dependency&gt;
    &lt;groupId&gt;org.postgresql&lt;/groupId&gt;
    &lt;artifactId&gt;postgresql&lt;/artifactId&gt;
    &lt;scope&gt;runtime&lt;/scope&gt;
&lt;/dependency&gt;
```

We can then resort to using [opentable](https://github.com/opentable/otj-pg-embedded) as the in memory engine by adding another dependency:

``` xml
&lt;dependency&gt;
    &lt;groupId&gt;com.opentable.components&lt;/groupId&gt;
    &lt;artifactId&gt;otj-pg-embedded&lt;/artifactId&gt;
    &lt;version&gt;0.13.1&lt;/version&gt;
    &lt;scope&gt;compile&lt;/scope&gt;
&lt;/dependency&gt;
```

Finally, wherever we want the embedded database, we can spin it up with default settings like:

``` java
package com.nickolasfisher.flywaystuff;

... imports ...

@Configuration
@ComponentScan
@Profile(&#34;dev&#34;)
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

Next up, we&#39;ll look at using [Flyway](https://flywaydb.org/) to run idempotent database migration scripts against our database on application startup, giving the application flexible and full control over the state of the schemas it owns.


