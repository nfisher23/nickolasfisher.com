---
title: "How to Configure Prometheus to Scrape and Aggregate Data From a Spring Boot 2.x Application"
date: 2020-05-30T20:33:50
draft: false
tags: [java, spring, DevOps, maven, prometheus]
---

You can see the source code for this post [on Github](https://github.com/nfisher23/prometheus-metrics-ex).

Following up on the last post \[ [How to Expose Meaningful Prometheus Metrics In a Spring Boot 2.x Application](https://nickolasfisher.com/blog/how-to-expose-meaningful-prometheus-metrics-in-a-spring-boot-2x-application)\], if we have metrics exposed but they don't go anywhere, are there metrics exposed at all?

Yes, there are metrics exposed, they're just not very useful. What we really want is to aggregate them and ship them to a data store so that we can view their evolution over time.

I'm going to use docker compose as a simple way to illustrate what you would need to do here. While you can run docker compose in a production environment, it has clearly lost (at this point - mid 2020) to kubernetes. I would recommend you either learn kubernetes or use virtual machines if you are planning on moving this to production.

### Get the app running

We'll have to get the application running in our little docker compose network first. So we need to set up a [Dockerfile](https://docs.docker.com/engine/reference/builder/) and throw it in the root directory:

```
FROM maven

RUN mkdir -p /app

COPY ./ /app/

ENTRYPOINT cd /app &amp;&amp; mvn spring-boot:run

```

At this point, we can set up the **docker-compose.yml**, which will represent a production like environment on our local machine:

```yaml
version: '3'
  # `docker-compose build` to rebuild
  app:
    build:
      context: ../
    volumes:
      - /home/nick/.m2:/root/.m2
    environment:
      - SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/local
    depends_on:
      - db
    ports:
      - 9000:8080

  db:
    image: postgres
    ports:
      - 5432:5432
    env_file:
      - database.env

```

We are leveraging the isolated network that docker compose creates for us in this process and we are also leveraging spring configuration override. **SPRING\_DATASOURCE\_URL** is the same as if we
would have specified a property in our **application.yml** that had something like:

```yaml
spring.datasource.url: jdbc:postgresql://db:5432/local
```

When we tell spring boot to look up the datasource with the name **db**, we are deferring to that docker compose network, where **db** resolves to the ip address where the postgres container is set up. This will by default build the application as determined by the Dockerfile, then start it up. You should be able to run:

```
$ docker-compose up -d
$ curl localhost:9000/actuator/prometheus

```

And see some prometheus metrics output.

To wire up prometheus, we will want to [use a built in prometheus image](https://hub.docker.com/r/prom/prometheus/) available on docker hub. We can add that to the **services** section in our docker compose file like so:

```yaml
  prom:
    image: prom/prometheus
    ports:
      - 9090:9090
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    depends_on:
      - app

  graf:
    image: grafana/grafana
    privileged: true
    ports:
      - 3000:3000
    depends_on:
      - prom
    volumes:
      - ./graf-data:/var/lib/grafana # note: need `chmod 777 graf-data` to do this

```

[Grafana](https://grafana.com/) is an open source graphing solution, commonly used with prometheus. I've included it here because it makes it much easier to digest and analyze the data once it gets in there. It's also just very commonly used with prometheus.

You will also need to set up your **prometheus.yml** file to find and scrape your application:

```yaml
global:
  scrape_interval:     15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
# - "first_rules.yml"
# - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label `job=` to any timeseries scraped from this config.
  - job_name: 'prometheus'
    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: 'spring-actuator'
    metrics_path: '/actuator/prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['app:8080'] # run ifconfig and get host ip

```

The really important part of this config, once again leveraging the DNS in the docker compose file, is:

```yaml
  - job_name: 'spring-actuator'
    metrics_path: '/actuator/prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['app:8080'] # run ifconfig and get host ip

```

This tells prometheus to scrape our application every five seconds, and the URL to resolve to is our exposed **/actuator/prometheus**. To run the example [provided in the source code](https://github.com/nfisher23/prometheus-metrics-ex), you will have to first create and modify a file to have the right permissions, then you can start it up:

```
$ mkdir graf-data &amp;&amp; chmod 777 graf-data
$ docker-compose up -d

```

After everything downloads and comes up properly, you can get to grafana at port 3000 or prometheus on port 9090, and you should see the data flowing from our application to make it so.
