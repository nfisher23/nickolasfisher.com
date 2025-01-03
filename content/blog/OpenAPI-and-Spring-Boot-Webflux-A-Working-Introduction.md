---
title: "OpenAPI and Spring Boot Webflux: A Working Introduction"
date: 2020-08-01T00:00:00
draft: false
---

The [OpenAPI Specification](http://spec.openapis.org/oas/v3.0.3) is an &#34;industry standard&#34; way of declaring the API interface. As REST APIs using JSON have dominated the way we move data around in most organizations and on the internet, particularly in service oriented architectures, and as documentation at almost every company has been written once, read a couple of times, then lost to the wind, smart people have figured out that they can put the documentation for their services living with the code--better yet, displayed while the app is running.

Let&#39;s set this up for spring boot webflux and start messing with it.

## Bootstrap the Application

Use the [spring boot initalizr](https://start.spring.io/) to create an application with the &#34;reactive web&#34; option. Then add this to your dependencies:

``` xml
        &lt;dependency&gt;
            &lt;groupId&gt;org.springdoc&lt;/groupId&gt;
            &lt;artifactId&gt;springdoc-openapi-webflux-ui&lt;/artifactId&gt;
            &lt;version&gt;1.4.4&lt;/version&gt;
        &lt;/dependency&gt;

```

If you start up your application:

``` bash
mvn spring-boot:run

```

Then you can go into another terminal and see this in action:

``` bash
$ curl localhost:8080/v3/api-docs | json_pp
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   180  100   180    0     0    584      0 --:--:-- --:--:-- --:--:--   584
{
   &#34;components&#34; : {},
   &#34;openapi&#34; : &#34;3.0.1&#34;,
   &#34;paths&#34; : {},
   &#34;servers&#34; : [
      {
         &#34;url&#34; : &#34;http://localhost:8080&#34;,
         &#34;description&#34; : &#34;Generated server url&#34;
      }
   ],
   &#34;info&#34; : {
      &#34;version&#34; : &#34;v0&#34;,
      &#34;title&#34; : &#34;OpenAPI definition&#34;
   }
}

```

You can also navigate to **http://localhost:8080/swagger-ui.html** by default and poke around. You won&#39;t see any operations defined yet, we&#39;re about to do that.

Let&#39;s create a simple entity and a simple controller and try that again:

``` java
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

``` java
@RestController
public class DocumentedController {

    @GetMapping(&#34;/hello&#34;)
    public Mono&lt;ResponseEntity&lt;Hello&gt;&gt; getHello() {
        Hello hello = new Hello();
        hello.setFirstName(&#34;yeah&#34;);
        hello.setLastName(&#34;bauer&#34;);
        return Mono.just(ResponseEntity.ok(hello));
    }

    @PostMapping(&#34;/hello&#34;)
    public Mono&lt;ResponseEntity&lt;Void&gt;&gt; postHello(Hello hello) {
        return Mono.just(ResponseEntity.accepted().build());
    }
}

```

If you reboot the application then hit **/v3/api-docs** again, you will see a huge json object including:

``` json
....
   &#34;paths&#34; : {
      &#34;/hello&#34; : {
         &#34;post&#34; : {
            &#34;operationId&#34; : &#34;postHello&#34;,
            &#34;tags&#34; : [
               &#34;documented-controller&#34;
            ],
            &#34;requestBody&#34; : {
               &#34;content&#34; : {
                  &#34;application/json&#34; : {
                     &#34;schema&#34; : {
                        &#34;$ref&#34; : &#34;#/components/schemas/Hello&#34;
                     }
                  }
               }
            },
            &#34;responses&#34; : {
               &#34;200&#34; : {
                  &#34;description&#34; : &#34;OK&#34;
               }
            }
         },
....

```

If we then modify our DTO model with any constraints included in the **javax.validation.constraints.\*** module, we can also see that in the json blob and in the swagger UI:

``` java
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

Reboot the app and you&#39;ll see a section on that api docs endpoint:

``` json
   &#34;components&#34; : {
      &#34;schemas&#34; : {
         &#34;Hello&#34; : {
            &#34;type&#34; : &#34;object&#34;,
            &#34;required&#34; : [
               &#34;lastName&#34;
            ],
            &#34;properties&#34; : {
               &#34;firstName&#34; : {
                  &#34;type&#34; : &#34;string&#34;,
                  &#34;maxLength&#34; : 250,
                  &#34;minLength&#34; : 0
               },
               &#34;lastName&#34; : {
                  &#34;type&#34; : &#34;string&#34;
               }
            }
         }
      }
   }

```

If we want to modify the description or get more in depth about certain edge cases, response codes, etc., there are some fun annotations we can use:

``` java
@RestController
public class DocumentedController {

    @Operation(summary = &#34;wattt&#34;, responses = {
            @ApiResponse(description = &#34;woot&#34;, responseCode = &#34;202&#34;)
    })
    @GetMapping(&#34;/hello&#34;)
    public Mono&lt;ResponseEntity&lt;Hello&gt;&gt; getHello() {
        Hello hello = new Hello();
        hello.setFirstName(&#34;yeah&#34;);
        hello.setLastName(&#34;bauer&#34;);
        return Mono.just(ResponseEntity.ok(hello));
    }

    @PostMapping(&#34;/hello&#34;)
    public Mono&lt;ResponseEntity&lt;Void&gt;&gt; postHello(Hello hello) {
        return Mono.just(ResponseEntity.accepted().build());
    }
}

```

You will notice a change in both the swagger UI as well as the api docs endpoint. Feel free to take a closer look at [the documentation](https://springdoc.org/) (in particular, check out the [Frequently Asked Questions](https://springdoc.org/faq.html)) to get an idea of all the options available to you!


