---
title: "How to Expose Meaningful Prometheus Metrics In a Spring Boot 2.x Application"
date: 2020-05-30T19:21:40
draft: false
tags: [java, spring, DevOps, postgreSQL, prometheus]
---

The source code for this post can be found [on Github](https://github.com/nfisher23/prometheus-metrics-ex).

[Prometheus](https://prometheus.io/) is a metrics aggregator with its own presumed format. The basic idea is to have the application gather a set of custom metrics, then periodically collect (or "scrape") the metrics and send them off to a prometheus server. This server will store the data in its database, and you can thus view the evolution of your application's metrics over time.

Spring boot has out of the box support for prometheus, but it requires a bit of bootstrapping. That will be the subject of this post.

### Start Getting Any Metrics At All

You can [spin up a spring boot application](https://start.spring.io/) with the initializr, select MVC with actuator, then add some dependencies to your pom:

```xml
        <!-- Micormeter core dependecy  -->
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-core</artifactId>
        </dependency>
        <!-- Micrometer Prometheus registry  -->
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-registry-prometheus</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>

```

With that in place, if you start up the application and hit the prometheus endpoint, you will get a 404 response:

```
~$ curl localhost:8080/actuator/prometheus
{"timestamp":"2020-06-06T19:50:39.925+0000","status":404,"error":"Not Found","message":"No message available","path":"/actuator/prometheus"}

```

That's because you have to enable the prometheus endpoint in the **application.yml**:

```yaml
management:
  endpoint:
    metrics:
      enabled: true
    prometheus:
      enabled: true
  endpoints:
    web:
      exposure:
        include: metrics,info,health,prometheus

```

Now if you start up the application, you'll start seeing some metrics come out:

```
$ curl localhost:8080/actuator/prometheus | grep jvm_memory_used_bytes
# HELP jvm_memory_used_bytes The amount of used memory
# TYPE jvm_memory_used_bytes gauge
jvm_memory_used_bytes{area="heap",id="G1 Survivor Space",} 7340032.0
jvm_memory_used_bytes{area="heap",id="G1 Old Gen",} 1.4454272E7
jvm_memory_used_bytes{area="nonheap",id="Metaspace",} 4.183572E7
jvm_memory_used_bytes{area="nonheap",id="CodeHeap 'non-nmethods'",} 1227392.0
jvm_memory_used_bytes{area="heap",id="G1 Eden Space",} 1.01711872E8
jvm_memory_used_bytes{area="nonheap",id="Compressed Class Space",} 5336000.0
jvm_memory_used_bytes{area="nonheap",id="CodeHeap 'non-profiled nmethods'",} 9015552.0

```

### Adding a Database - Free Metrics

Spring boot will start aggregating metrics for you automatically if it falls into a certain category. Let's say we add a postgres data source to our application by adding this to our **application.yml**:

```yaml
spring:
  datasource:
    driver-class-name: org.postgresql.Driver
    password: pswd
    username: jack
    url: jdbc:postgresql://127.0.0.1:5432/local

```

Also make sure to add this dependency to your **pom.xml**:

```xml
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <scope>runtime</scope>
        </dependency>

```

Finally, let's set up a docker-compose file to get us a local database to work with:

```yaml
version: "3"
services:
  db:
    image: postgres
    ports:
      - 5432:5432
    env_file:
      - database.env
```

We can make the **database.env** file look like:

```
POSTGRES_USER=jack
POSTGRES_PASSWORD=pswd
POSTGRES_DB=local

```

And with that in place, go ahead and bring up the docker-compose database and start the application:

```
$ docker-compose up -d
```

(in directory with **pom.xml**)

```
mvn spring-boot:run
```

If you then ask for prometheus metrics, you'll see quite a few that include data on the Hikari datasource connection pool:

```
$ curl localhost:8080/actuator/prometheus | grep hikaricp_connections_
hikaricp_connections_max{pool="HikariPool-1",} 10.0
# HELP hikaricp_connections_min Min connections
# TYPE hikaricp_connections_min gauge
hikaricp_connections_min{pool="HikariPool-1",} 10.0
# HELP hikaricp_connections_pending Pending threads
# TYPE hikaricp_connections_pending gauge
hikaricp_connections_pending{pool="HikariPool-1",} 0.0
```

With this, you're off to the races.
