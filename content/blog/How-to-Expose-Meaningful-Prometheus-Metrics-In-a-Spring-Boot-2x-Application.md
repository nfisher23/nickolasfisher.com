---
title: "How to Expose Meaningful Prometheus Metrics In a Spring Boot 2.x Application"
date: 2020-05-01T00:00:00
draft: false
---

The source code for this post can be found [on Github](https://github.com/nfisher23/prometheus-metrics-ex).

[Prometheus](https://prometheus.io/) is a metrics aggregator with its own presumed format. The basic idea is to have the application gather a set of custom metrics, then periodically collect (or &#34;scrape&#34;) the metrics and send them off to a prometheus server. This server will store the data in its database, and you can thus view the evolution of your application&#39;s metrics over time.

Spring boot has out of the box support for prometheus, but it requires a bit of bootstrapping. That will be the subject of this post.

### Start Getting Any Metrics At All

You can [spin up a spring boot application](https://start.spring.io/) with the initializr, select MVC with actuator, then add some dependencies to your pom:

``` xml
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

``` yaml
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
