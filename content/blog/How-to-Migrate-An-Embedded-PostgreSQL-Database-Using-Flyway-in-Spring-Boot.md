---
title: "How to Migrate An Embedded PostgreSQL Database Using Flyway in Spring Boot"
date: 2019-04-20T16:00:34
draft: false
---

The source code for this post can be found [on GitHub](https://github.com/nfisher23/postgres-flyway-example).

[Flyway](https://flywaydb.org/) is a database migration tool. _Migrating_ a database generally means that you are making a change to the way the database currently structures its data. It could also mean you are adding stuff like custom stored procedures or indexes to help speed up queries. Either way, migrating databases is easily the most difficult part of any deployment strategy--Flyway makes this process as painless as possible because it will, by default, _only run migration scripts that haven&#39;t yet run_.

If you&#39;re also using an [Embedded PostgreSQL database](https://nickolasfisher.com/blog/How-to-Create-an-Embedded-PostgreSQL-Database-With-Spring-Boot) to handle database parity between environments, you will then have a much, much higher level of confidence that your changes will not blow everything up, as well as your embedded database precisely representing the data in the production database. This is a huge win for productivity and for reducing errors.

The first thing that we will need to do is add the flyway dependency which, if you&#39;re using Maven, is:

```xml
&lt;dependency&gt;
    &lt;groupId&gt;org.flywaydb&lt;/groupId&gt;
    &lt;artifactId&gt;flyway-core&lt;/artifactId&gt;
&lt;/dependency&gt;
```

While there is some [Spring Boot magic for running migration scripts with Flyway](https://docs.spring.io/spring-boot/docs/current/reference/html/howto-database-initialization.html), the magic can often make it hard to customize it (and, eventually, you will most likely need to customize it). With a bit of work we can remove the magic and get exactly what we want, using code. To prevent the magic from getting in the way of this example, be sure to add this to your **application.yml**:

```yaml
spring.flyway.enabled: false

```

If we have our in memory database from the last post set up using a Spring Profile called &#34;dev&#34;:

```java
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

We can use **@PostConstruct** to run our migration immediately after the application context wiring itself:

```java
package com.nickolasfisher.flywaystuff;

... imports ...

@Component
public class Migrate {

    @Autowired
    DataSource ds;

    @PostConstruct
    public void migrateWithFlyway() {
        Flyway flyway = Flyway.configure()
                .dataSource(ds)
                .locations(&#34;db/migration&#34;)
                .load();

        flyway.migrate();
    }
}
```

Here, any migration scripts found in our **src/main/resources/db/migration** directory will be run in an idempotent fashion. You can read up on the [conventions that flyway uses to decide the order of migration scripts](https://flywaydb.org/getstarted/how), but for this example we will add two SQL files. The first I&#39;ll call **V1\_\_init.sql**:

```sql
CREATE TABLE employee (id int, name text);
```

The second will be **V2\_\_update.sql**:

```sql
ALTER TABLE employee ALTER COLUMN id SET NOT NULL;
```

We can verify that this works with something like this:

```java
package com.nickolasfisher.flywaystuff;

... imports ...

@Component
public class RegularWriter {

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Scheduled(fixedRate = 5000)
    public void pollConsistently() {
        jdbcTemplate.execute(&#34;INSERT INTO employee (id, name) VALUES (1, &#39;jack&#39;)&#34;);
        jdbcTemplate.query(&#34;SELECT * FROM employee&#34;, (rs) -&gt; {
            rs.next();
            int a = rs.getInt(&#34;id&#34;);
            System.out.println(a);
            return a;
        });
        System.out.println(&#34;writing...&#34;);
    }
}

```

If you run:

```bash
$ mvn clean install
```

And then:

```bash
$ java -jar target/flywaystuff-1.0.jar
```

You will see the application come up successfully and execute/query the database in memory every 5 seconds.
