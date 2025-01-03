---
title: "How to Selectively Allow Cross Origin Resource Sharing in Spring Boot"
date: 2019-05-18T19:12:46
draft: false
tags: [java, spring, webdev]
---

A single page application (SPA) architecture usually involves an end user getting a smattering of javascript files when he/she makes a request to a URL endpoint. After the javascript files load and start executing code, they usually make AJAX calls to interact with the back end from that point onwards. This pairs nicely with a microservice architecture based on REST over HTTP, since the front end SPA can effectively act as a client to any microservice that it needs information from.

[Cross Origin Resource Sharing](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) is a mechanism that browsers enforce to try and prevent an AJAX call being made to a server that is not properly configured to receive it. This is a strict mechanism: if the browser isn&#39;t using the exact URI resource and port number to request the resource, then the browser enforces this policy.

Let&#39;s say you have a website, spa.nickolasfisher.com, and users of your site get their smattering of javascript files and small html file when they request your home page. Then you want to make a backend request to api.nickolasfisher.com, since that&#39;s the gateway for the microservices you need to interact with. Well, if it&#39;s a GET request, then the browser will let you send the request directly, but will require a response header like:

```
Access-Control-Allow-Origin: https://spa.nickolasfisher.com
```

If it doesn&#39;t see that (it also supports wildcards, so it doesn&#39;t have to be that exactly), then the response will not make it into the sandbox. Further, if you try to make any request to the backend that is not a GET request (e.g. POST, PUT, etc.), the browser will send a &#34;preflight&#34; request to the backend via the OPTIONS method that wants a collection of headers like:

- Access-Control-Allow-Origin
- Access-Control-Allow-Methods
- Access-Control-Allow-Headers
- Access-Control-Max-Age

It will make this request to the same endpoint that your browser wants to talk to, so while you could fairly easily do this manually, it definitely sniffs of DRY in a very real way.

Thankfully, Spring Boot provides a very easy mechanism to set a cross origin policy that can be defined in one place. In this example, I set up a CORS mapping to allow all requests for a default Angular application that gets served at localhost:4200:

```java
@Configuration
@Profile(&#34;dev&#34;)
public class AppConfig {

  @Bean
  public WebMvcConfigurer corsConfigurer() {
    return new WebMvcConfigurer() {
      @Override
      public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping(&#34;/**&#34;).allowedOrigins(&#34;http://localhost:4200&#34;);
      }
    };
  }
}

```

For more information, take a look at the [current spring documentation on CORS support](https://docs.spring.io/spring/docs/current/spring-framework-reference/web.html#mvc-cors).
