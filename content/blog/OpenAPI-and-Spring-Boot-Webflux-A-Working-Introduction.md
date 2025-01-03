---
title: "OpenAPI and Spring Boot Webflux: A Working Introduction"
date: 2020-08-01T23:59:33
draft: false
tags: [java, spring, maven, reactive, webflux]
---

The [OpenAPI Specification](http://spec.openapis.org/oas/v3.0.3) is an "industry standard" way of declaring the API interface. As REST APIs using JSON have dominated the way we move data around in most organizations and on the internet, particularly in service oriented architectures, and as documentation at almost every company has been written once, read a couple of times, then lost to the wind, smart people have figured out that they can put the documentation for their services living with the code--better yet, displayed while the app is running.

Let's set this up for spring boot webflux and start messing with it.

## Bootstrap the Application

Use the [spring boot initalizr](https://start.spring.io/) to create an application with the "reactive web" option. Then add this to your dependencies:

```xml
        <dependency>
            <groupId>org.springdoc</groupId>
            <artifactId>springdoc-openapi-webflux-ui</artifactId>
            <version>1.4.4</version>
        </dependency>

```

If you start up your application:

```bash
mvn spring-boot:run

```

Then you can go into another terminal and see this in action:

```bash
$ curl localhost:8080/v3/api-docs | json_pp
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   180  100   180    0     0    584      0 --:--:-- --:--:-- --:--:--   584
{
   "components" : {},
   "openapi" : "3.0.1",
   "paths" : {},
   "servers" : [
      {
         "url" : "http://localhost:8080",
         "description" : "Generated server url"
      }
   ],
   "info" : {
      "version" : "v0",
      "title" : "OpenAPI definition"
   }
}

```

You can also navigate to **http://localhost:8080/swagger-ui.html** by default and poke around. You won't see any operations defined yet, we're about to do that.

Let's create a simple entity and a simple controller and try that again:

```java
public class Hello {
    private String firstName;

    private String lastName;

    public String getFirstName() {
        return firstName;
    }

    public void setFirstName(String firstName) {
        this.firstName = firstName;
    }

    public String getLastName() {
        return lastName;
    }

    public void setLastName(String lastName) {
        this.lastName = lastName;
    }
}

```

Now the controller:

```java
@RestController
public class DocumentedController {

    @GetMapping("/hello")
    public Mono<ResponseEntity<Hello>> getHello() {
        Hello hello = new Hello();
        hello.setFirstName("yeah");
        hello.setLastName("bauer");
        return Mono.just(ResponseEntity.ok(hello));
    }

    @PostMapping("/hello")
    public Mono<ResponseEntity<Void>> postHello(Hello hello) {
        return Mono.just(ResponseEntity.accepted().build());
    }
}

```

If you reboot the application then hit **/v3/api-docs** again, you will see a huge json object including:

```json
....
   "paths" : {
      "/hello" : {
         "post" : {
            "operationId" : "postHello",
            "tags" : [
               "documented-controller"
            ],
            "requestBody" : {
               "content" : {
                  "application/json" : {
                     "schema" : {
                        "$ref" : "#/components/schemas/Hello"
                     }
                  }
               }
            },
            "responses" : {
               "200" : {
                  "description" : "OK"
               }
            }
         },
....

```

If we then modify our DTO model with any constraints included in the **javax.validation.constraints.\*** module, we can also see that in the json blob and in the swagger UI:

```java
import javax.validation.constraints.NotNull;
import javax.validation.constraints.Size;

public class Hello {
    @Size(max = 250)
    private String firstName;

    @NotNull
    private String lastName;

...getters and setters...
}

```

Reboot the app and you'll see a section on that api docs endpoint:

```json
   "components" : {
      "schemas" : {
         "Hello" : {
            "type" : "object",
            "required" : [
               "lastName"
            ],
            "properties" : {
               "firstName" : {
                  "type" : "string",
                  "maxLength" : 250,
                  "minLength" : 0
               },
               "lastName" : {
                  "type" : "string"
               }
            }
         }
      }
   }

```

If we want to modify the description or get more in depth about certain edge cases, response codes, etc., there are some fun annotations we can use:

```java
@RestController
public class DocumentedController {

    @Operation(summary = "wattt", responses = {
            @ApiResponse(description = "woot", responseCode = "202")
    })
    @GetMapping("/hello")
    public Mono<ResponseEntity<Hello>> getHello() {
        Hello hello = new Hello();
        hello.setFirstName("yeah");
        hello.setLastName("bauer");
        return Mono.just(ResponseEntity.ok(hello));
    }

    @PostMapping("/hello")
    public Mono<ResponseEntity<Void>> postHello(Hello hello) {
        return Mono.just(ResponseEntity.accepted().build());
    }
}

```

You will notice a change in both the swagger UI as well as the api docs endpoint. Feel free to take a closer look at [the documentation](https://springdoc.org/) (in particular, check out the [Frequently Asked Questions](https://springdoc.org/faq.html)) to get an idea of all the options available to you!
