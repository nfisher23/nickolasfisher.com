---
title: "A Concise Guide to Using Jasypt In Spring Boot for Configuration Encryption"
date: 2020-05-23T01:58:12
draft: false
---

[Jasypt](http://www.jasypt.org/) is a simple encryption library. You can use it to encrypt anything, but one good use case is just encrypting your application configuration directly in your config file, so that if someone obtained access to your source control directory or had a copy of your source code, they would not also have access to any of your secrets.

Spring boot is...you know what spring boot is, let&#39;s get started.

### Encrypting the secret via the CLI

You can [download the jasypt CLI zip file](https://github.com/jasypt/jasypt) directly from github (you&#39;ll need java, but I know you already have that because you&#39;re writing a spring boot application), and run:

```
unzip jasypt-&lt;version&gt;-dist.zip
cd jasypt*
chmod &#43;x bin/*
./bin/encrypt.sh input=&lt;thing-you-want-to-decrypt&gt; password=&lt;your-password&gt;
```

For example, I have a secret database password called **immapanda123** and I have a password named **youcantguessme**:

```
./bin/encrypt.sh input=immapanda123 password=youcantguessme

```

What it outputs is non deterministic, if you run it over and over again you&#39;ll get a different string. Here&#39;s one that it generated for me:

```
2WCwqzn&#43;ClzAP44UFAxiHYcKxJ9uiJQU
```

**Important note**: the CLI is using the default algorithm of:

```
PBEWithMD5AndDES
```

And a default [IV generator](https://en.wikipedia.org/wiki/Initialization_vector) of:

```
org.jasypt.iv.NoIvGenerator
```

The newest integration between jasypt and spring boot means that these defaults do not align, see the [github notes on the 3.xx release](https://github.com/ulisesbocchio/jasypt-spring-boot#update-11242019-version-300-release-includes). I&#39;ll show you how to deal with that in just a bit.

### Using the secret in a spring boot application

Continuing with the above example...

Start by pulling down a spring boot project, e.g. the spring initializer. Then add this dependency:

```xml
        &lt;dependency&gt;
            &lt;groupId&gt;com.github.ulisesbocchio&lt;/groupId&gt;
            &lt;artifactId&gt;jasypt-spring-boot-starter&lt;/artifactId&gt;
            &lt;version&gt;3.0.2&lt;/version&gt;
        &lt;/dependency&gt;

```

Set up a configuration class called **AppConfig** like:

```java
@Component
public class AppConfig {

    @Value(&#34;${my.secret}&#34;)
    private String mySecret;

    public String getMySecret() {
        return mySecret;
    }

    public void setMySecret(String mySecret) {
        this.mySecret = mySecret;
    }
}

```

And a controller like:

```java
@RestController
public class MyController {

    private final AppConfig config;

    public MyController(AppConfig config) {
        this.config = config;
    }

    @GetMapping(&#34;/secret&#34;)
    public ResponseEntity getSecret() {
        return ResponseEntity.ok(config.getMySecret());
    }
}

```

Don&#39;t forget to add the **@EnableEncryptableProperties** annotation:

```java
@SpringBootApplication
@EnableEncryptableProperties
public class JasyptExampleApplication {

    public static void main(String[] args) {
        SpringApplication.run(JasyptExampleApplication.class, args);
    }

}

```

To use the password we just generated, your **application.yml** will have to look like:

```yaml
jasypt:
  encryptor:
    password: youcantguessme
    algorithm: PBEWithMD5AndDES
    iv-generator-classname: org.jasypt.iv.NoIvGenerator

my.secret: ENC(2WCwqzn&#43;ClzAP44UFAxiHYcKxJ9uiJQU)

```

You can start up your application and

```
$ curl localhost:8080/secret
immapanda123
```

### Encrypting with New Defaults

In the latest version of spring boot and the jasypt starter 3.xx, the default algorithm is:

```
PBEWITHHMACSHA512ANDAES_256

```

This type of encryption does not work without a legit IV generator, and the jasypt cli by default does not use an iv generator. The spring boot default is:

```
org.jasypt.iv.RandomIvGenerator

```

So to use the CLI to generate an out-of-the-box compatible password you&#39;ll have to encrypt it like:

```
./encrypt.sh input=immapanda123 password=youcantguessme algorithm=PBEWITHHMACSHA512ANDAES_256 ivGeneratorClassName=org.jasypt.iv.RandomIvGenerator

```

This is also non deterministic, here&#39;s one output I got:

```
HU&#43;pHQRhFmvgZ0p&#43;AK1zMHP0ayzyu3liyGLbHvzNy1Lu6gkI&#43;xapltrdescWNdAv
```

Your **application.yml** can now drop the _algorithm_ and _iv-generator-classname_ in the distinction:

```yaml
jasypt:
  encryptor:
    password: youcantguessme

my.secret: ENC(yVwuQNWRUgy7guzYcfdew3j4zyjTK4WB6MdJuiMZFfe0NRGD/ziX&#43;p73ORWNze3I)

```

And your application should start up and serve the secret at **localhost:8080/secret.**

### Actually Securing your App

There&#39;s no point in including the password that you used to encrypt your secrets in plaintext right next to your secret. In reality, you&#39;d have different [spring profiles](https://docs.spring.io/spring-boot/docs/current/reference/html/spring-boot-features.html#boot-features-profiles) with a different encryption password for each profile. Then you would override the encryptor password with an environment variable at runtime, on whatever server this thing runs on. For example, change your **application.yml** to look like:

```yaml
my.secret: ENC(yVwuQNWRUgy7guzYcfdew3j4zyjTK4WB6MdJuiMZFfe0NRGD/ziX&#43;p73ORWNze3I)
```

If you start up your app now with no changes you should see this error:

```
org.springframework.beans.factory.BeanCreationException: Error creating bean with name &#39;appConfig&#39;: Injection of autowired dependencies failed;
nested exception is java.lang.IllegalStateException: either &#39;jasypt.encryptor.password&#39; or one of
[&#39;jasypt.encryptor.private-key-string&#39;, &#39;jasypt.encryptor.private-key-location&#39;] must be provided for Password-based or Asymmetric encryption

```

You can provide one using environment variables. Start up your application from the command line like:

```
$ export JASYPT_ENCRYPTOR_PASSWORD=youcantguessme
$ java -jar target/*.jar

```

And your application should come up nice and fine.
