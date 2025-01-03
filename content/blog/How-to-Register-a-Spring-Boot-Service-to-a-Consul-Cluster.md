---
title: "How to Register a Spring Boot Service to a Consul Cluster"
date: 2019-05-01T00:00:00
draft: false
---

In a previous post, we saw [how to provision a simple consul client/server cluster using Ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Consul-ClientServer-Cluster-using-Ansible). We will now look at interacting with that cluster by showing how to register a spring boot application to it, using [spring cloud consul](https://cloud.spring.io/spring-cloud-consul/spring-cloud-consul.html).

First, pull up the [spring boot initializer](https://start.spring.io/). Select web and spring cloud, then download and unpack the project. Your pom.xml should look something like this:

``` xml
&lt;?xml version=&#34;1.0&#34; encoding=&#34;UTF-8&#34;?&gt;
&lt;project xmlns=&#34;http://maven.apache.org/POM/4.0.0&#34; xmlns:xsi=&#34;http://www.w3.org/2001/XMLSchema-instance&#34;
         xsi:schemaLocation=&#34;http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd&#34;&gt;
    &lt;modelVersion&gt;4.0.0&lt;/modelVersion&gt;
    &lt;parent&gt;
        &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
        &lt;artifactId&gt;spring-boot-starter-parent&lt;/artifactId&gt;
        &lt;version&gt;2.1.5.RELEASE&lt;/version&gt;
        &lt;relativePath/&gt; &lt;!-- lookup parent from repository --&gt;
    &lt;/parent&gt;
    &lt;groupId&gt;com.nickolasfisher&lt;/groupId&gt;
    &lt;artifactId&gt;consulregister&lt;/artifactId&gt;
    &lt;version&gt;0.0.1-SNAPSHOT&lt;/version&gt;
    &lt;name&gt;consulregister&lt;/name&gt;
    &lt;description&gt;Sample app that registers to Consul&lt;/description&gt;

    &lt;properties&gt;
        &lt;java.version&gt;11&lt;/java.version&gt;
        &lt;spring-cloud.version&gt;Greenwich.SR1&lt;/spring-cloud.version&gt;
    &lt;/properties&gt;

    &lt;dependencies&gt;
        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.cloud&lt;/groupId&gt;
            &lt;artifactId&gt;spring-cloud-starter-consul-discovery&lt;/artifactId&gt;
        &lt;/dependency&gt;

        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-web&lt;/artifactId&gt;
            &lt;version&gt;2.1.5.RELEASE&lt;/version&gt;
        &lt;/dependency&gt;

        &lt;dependency&gt;
            &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
            &lt;artifactId&gt;spring-boot-starter-test&lt;/artifactId&gt;
            &lt;scope&gt;test&lt;/scope&gt;
        &lt;/dependency&gt;
    &lt;/dependencies&gt;

    &lt;dependencyManagement&gt;
        &lt;dependencies&gt;
            &lt;dependency&gt;
                &lt;groupId&gt;org.springframework.cloud&lt;/groupId&gt;
                &lt;artifactId&gt;spring-cloud-dependencies&lt;/artifactId&gt;
                &lt;version&gt;${spring-cloud.version}&lt;/version&gt;
                &lt;type&gt;pom&lt;/type&gt;
                &lt;scope&gt;import&lt;/scope&gt;
            &lt;/dependency&gt;
        &lt;/dependencies&gt;
    &lt;/dependencyManagement&gt;

    &lt;build&gt;
        &lt;plugins&gt;
            &lt;plugin&gt;
                &lt;groupId&gt;org.springframework.boot&lt;/groupId&gt;
                &lt;artifactId&gt;spring-boot-maven-plugin&lt;/artifactId&gt;
            &lt;/plugin&gt;
        &lt;/plugins&gt;
    &lt;/build&gt;

&lt;/project&gt;

```

You will need the web dependency to allow Consul to check your health endpoint, and you will need the spring cloud dependency to have your application register to consul on startup time.

What remains is some spring boot automagic. If you took after the post on provisioning your consul cluster and [you started it using the sample code](https://github.com/nfisher23/some-ansible-examples/tree/master/consul-server), you will have a Consul agent running in client mode available at **192.168.56.212**, and it will be receiving communications on port **8500**. All you will need to make this happen is some changes to your **application.yml** inside of your resources folder:

``` yaml
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

``` bash
$ mvn spring-boot:run
```

After a bit, you should see your application register to consul with a log entry containing something similar to:

```
...Registering service with consul: NewService{id=&#39;consulregister&#39;, name=&#39;consulregister&#39;, tags=[secure=false], address=&#39;192.168.0.20&#39;, meta=null, port=8080, enableTagOverride=null, check=Check{script=&#39;null&#39;, interval=&#39;10s&#39;, ttl=&#39;null&#39;, http=&#39;http://192.168.0.20:8080/actuator/health&#39;, method=&#39;null&#39;, header={}, tcp=&#39;null&#39;, timeout=&#39;null&#39;, deregisterCriticalServiceAfter=&#39;null&#39;, tlsSkipVerify=null, status=&#39;null&#39;}, checks=null}

```

You can then ask consul to verify that it contains the service:

``` bash
$ curl http://192.168.68.212:8500/v1/agent/services | json_pp
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   202  100   202    0     0   197k      0 --:--:-- --:--:-- --:--:--  197k
{
   &#34;consulregister&#34; : {
      &#34;Port&#34; : 8080,
      &#34;Tags&#34; : [
         &#34;secure=false&#34;
      ],
      &#34;Address&#34; : &#34;192.168.0.20&#34;,
      &#34;ID&#34; : &#34;consulregister&#34;,
      &#34;Meta&#34; : {},
      &#34;Service&#34; : &#34;consulregister&#34;,
      &#34;Weights&#34; : {
         &#34;Warning&#34; : 1,
         &#34;Passing&#34; : 1
      },
      &#34;EnableTagOverride&#34; : false
   }
}

```

And you&#39;re good to go.


