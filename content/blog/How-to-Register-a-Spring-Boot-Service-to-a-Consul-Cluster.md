---
title: "How to Register a Spring Boot Service to a Consul Cluster"
date: 2019-05-25T16:24:46
draft: false
tags: [java, distributed systems, spring, consul]
---

In a previous post, we saw [how to provision a simple consul client/server cluster using Ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Consul-ClientServer-Cluster-using-Ansible). We will now look at interacting with that cluster by showing how to register a spring boot application to it, using [spring cloud consul](https://cloud.spring.io/spring-cloud-consul/spring-cloud-consul.html).

First, pull up the [spring boot initializer](https://start.spring.io/). Select web and spring cloud, then download and unpack the project. Your pom.xml should look something like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>2.1.5.RELEASE</version>
        <relativePath/> <!-- lookup parent from repository -->
    </parent>
    <groupId>com.nickolasfisher</groupId>
    <artifactId>consulregister</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>consulregister</name>
    <description>Sample app that registers to Consul</description>

    <properties>
        <java.version>11</java.version>
        <spring-cloud.version>Greenwich.SR1</spring-cloud.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-consul-discovery</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
            <version>2.1.5.RELEASE</version>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>

</project>

```

You will need the web dependency to allow Consul to check your health endpoint, and you will need the spring cloud dependency to have your application register to consul on startup time.

What remains is some spring boot automagic. If you took after the post on provisioning your consul cluster and [you started it using the sample code](https://github.com/nfisher23/some-ansible-examples/tree/master/consul-server), you will have a Consul agent running in client mode available at **192.168.56.212**, and it will be receiving communications on port **8500**. All you will need to make this happen is some changes to your **application.yml** inside of your resources folder:

```yaml
spring:
  application:
    name: consulregister
  cloud:
    consul:
      enabled: true
      port: 8500
      host: http://192.168.56.212:8500

```

You can then go to your application directory and run:

```bash
$ mvn spring-boot:run
```

After a bit, you should see your application register to consul with a log entry containing something similar to:

```
...Registering service with consul: NewService{id='consulregister', name='consulregister', tags=[secure=false], address='192.168.0.20', meta=null, port=8080, enableTagOverride=null, check=Check{script='null', interval='10s', ttl='null', http='http://192.168.0.20:8080/actuator/health', method='null', header={}, tcp='null', timeout='null', deregisterCriticalServiceAfter='null', tlsSkipVerify=null, status='null'}, checks=null}

```

You can then ask consul to verify that it contains the service:

```bash
$ curl http://192.168.68.212:8500/v1/agent/services | json_pp
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   202  100   202    0     0   197k      0 --:--:-- --:--:-- --:--:--  197k
{
   "consulregister" : {
      "Port" : 8080,
      "Tags" : [
         "secure=false"
      ],
      "Address" : "192.168.0.20",
      "ID" : "consulregister",
      "Meta" : {},
      "Service" : "consulregister",
      "Weights" : {
         "Warning" : 1,
         "Passing" : 1
      },
      "EnableTagOverride" : false
   }
}

```

And you're good to go.
