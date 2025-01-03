---
title: "How to Expose Meaningful Prometheus Metrics In a Spring Boot 2.x Application"
date: 2020-05-30T19:21:40
draft: false
tags: [java, spring, DevOps, postgreSQL, prometheus]
---

The source code for this post can be found [on Github](https://github.com/nfisher23/prometheus-metrics-ex).

[Prometheus](https://prometheus.io/) is a metrics aggregator with its own presumed format. The basic idea is to have the application gather a set of custom metrics, then periodically collect (or &#34;scrape&#34;) the metrics and send them off to a prometheus server. This server will store the data in its database, and you can thus view the evolution of your application&#39;s metrics over time.

Spring boot has out of the box support for prometheus, but it requires a bit of bootstrapping. That will be the subject of this post.

### Start Getting Any Metrics At All

You can [spin up a spring boot application](https://start.spring.io/) with the initializr, select MVC with actuator, then add some dependencies to your pom:

```xml
        &lt;!-- Micormeter core dependecy  --&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;io.micrometer&lt;/groupId&gt;
            &lt;artifactId&gt;micrometer-core&lt;/artifactId&gt;
        &lt;/dependency&gt;
        &lt;!-- Micrometer Prometheus registry  --&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;io.micrometer&lt;/groupId&gt;
            &lt;artifactId&gt;micrometer-registry-prometheus&lt;/artifactId&gt;
        &lt;/dependency&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-actuator&lt;/artifactId&gt;
        &lt;/dependency&gt;

```

With that in place, if you start up the application and hit the prometheus endpoint, you will get a 404 response:

```
~$ curl localhost:8080/actuator/prometheus
{&#34;timestamp&#34;:&#34;2020-06-06T19:50:39.925&#43;0000&#34;,&#34;status&#34;:404,&#34;error&#34;:&#34;Not Found&#34;,&#34;message&#34;:&#34;No message available&#34;,&#34;path&#34;:&#34;/actuator/prometheus&#34;}

```

That&#39;s because you have to enable the prometheus endpoint in the **application.yml**:

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

Now if you start up the application, you&#39;ll start seeing some metrics come out:

```
$ curl localhost:8080/actuator/prometheus | grep jvm_memory_used_bytes
# HELP jvm_memory_used_bytes The amount of used memory
# TYPE jvm_memory_used_bytes gauge
jvm_memory_used_bytes{area=&#34;heap&#34;,id=&#34;G1 Survivor Space&#34;,} 7340032.0
jvm_memory_used_bytes{area=&#34;heap&#34;,id=&#34;G1 Old Gen&#34;,} 1.4454272E7
jvm_memory_used_bytes{area=&#34;nonheap&#34;,id=&#34;Metaspace&#34;,} 4.183572E7
jvm_memory_used_bytes{area=&#34;nonheap&#34;,id=&#34;CodeHeap &#39;non-nmethods&#39;&#34;,} 1227392.0
jvm_memory_used_bytes{area=&#34;heap&#34;,id=&#34;G1 Eden Space&#34;,} 1.01711872E8
jvm_memory_used_bytes{area=&#34;nonheap&#34;,id=&#34;Compressed Class Space&#34;,} 5336000.0
jvm_memory_used_bytes{area=&#34;nonheap&#34;,id=&#34;CodeHeap &#39;non-profiled nmethods&#39;&#34;,} 9015552.0

```

### Adding a Database - Free Metrics

Spring boot will start aggregating metrics for you automatically if it falls into a certain category. Let&#39;s say we add a postgres data source to our application by adding this to our **application.yml**:

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
        &lt;dependency&gt;
            &lt;groupId&gt;org.postgresql&lt;/groupId&gt;
            &lt;artifactId&gt;postgresql&lt;/artifactId&gt;
            &lt;scope&gt;runtime&lt;/scope&gt;
        &lt;/dependency&gt;

```

Finally, let&#39;s set up a docker-compose file to get us a local database to work with:

```yaml
version: &#34;3&#34;
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

If you then ask for prometheus metrics, you&#39;ll see quite a few that include data on the Hikari datasource connection pool:

```
$ curl localhost:8080/actuator/prometheus | grep hikaricp_connections_
hikaricp_connections_max{pool=&#34;HikariPool-1&#34;,} 10.0
# HELP hikaricp_connections_min Min connections
# TYPE hikaricp_connections_min gauge
hikaricp_connections_min{pool=&#34;HikariPool-1&#34;,} 10.0
# HELP hikaricp_connections_pending Pending threads
# TYPE hikaricp_connections_pending gauge
hikaricp_connections_pending{pool=&#34;HikariPool-1&#34;,} 0.0
```

With this, you&#39;re off to the races.
