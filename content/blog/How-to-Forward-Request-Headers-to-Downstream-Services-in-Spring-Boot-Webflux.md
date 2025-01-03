---
title: "How to Forward Request Headers to Downstream Services in Spring Boot Webflux"
date: 2020-07-19T19:39:10
draft: false
---

The source code for this post [can be found on Github](https://github.com/nfisher23/reactive-programming-webflux/tree/master/context-api).

When you make the switch to a reactive codebase, [ThreadLocal](https://docs.oracle.com/javase/7/docs/api/java/lang/ThreadLocal.html) becomes effectively off limits to you, because you aren&#39;t guaranteed that the thread that starts the request processing remains the same, even if it&#39;s the same HTTP request. This has caused pain in many places: the original implementation of spring security, for example, relied very heavily on ThreadLocal variables to store state that happened in the start of the request, and then reuse the information stored in those variables later on to make access control decisions. [Neflix spoke of their pain migrating to a reactive stack](https://netflixtechblog.com/zuul-2-the-netflix-journey-to-asynchronous-non-blocking-systems-45947377fb5c), when they had relied so heavily on ThreadLocal variables in most of their shared libraries.

If you need to store state through the lifecycle of a request in a reactive stack, we have to go a little bit of a different way. Thankfully, in the case of project reactor, they have come up with a nifty abstraction that is very similar to ThreadLocal: [Context](https://projectreactor.io/docs/core/release/reference/#context). I elected to use Context to automatically forward a known request header downstream, which is very commonly needed in a microservices architecture, for example passing around an authentication token or tracking a user span.

## Simple Echo Server

To make things a little easier for me, I borrowed [a really simple python server that just prints out the request and the response](https://gist.github.com/huyng/814831). Note that I had to modify it slightly in order to get webflux to play nice with it and I also changed the port, the full code is here:

```python
#!/usr/bin/env python
# Reflects the requests from HTTP methods GET, POST, PUT, and DELETE
# Written by Nathan Hamiel (2010)

from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
from optparse import OptionParser

class RequestHandler(BaseHTTPRequestHandler):

    def do_GET(self):

        request_path = self.path

        print(&#34;\n----- Request Start -----&gt;\n&#34;)
        print(request_path)
        print(self.headers)
        print(&#34;&lt;----- Request End -----\n&#34;)

        self.send_response(200)
        self.send_header(&#34;Set-Cookie&#34;, &#34;foo=bar&#34;)
        self.end_headers()

    def do_POST(self):

        request_path = self.path

        print(&#34;\n----- Request Start -----&gt;\n&#34;)
        print(request_path)

        request_headers = self.headers
        content_length = request_headers.getheaders(&#39;content-length&#39;)
        length = int(content_length[0]) if content_length else 0

        print(request_headers)
        print(self.rfile.read(length))
        print(&#34;&lt;----- Request End -----\n&#34;)

        self.send_response(200)
        self.end_headers()

    do_PUT = do_POST
    do_DELETE = do_GET

def main():
    port = 9000
    print(&#39;Listening on localhost:%s&#39; % port)
    server = HTTPServer((&#39;&#39;, port), RequestHandler)
    server.serve_forever()


if __name__ == &#34;__main__&#34;:
    parser = OptionParser()
    parser.usage = (&#34;Creates an http-server that will echo out any GET or POST parameters\n&#34;
                    &#34;Run:\n\n&#34;
                    &#34;   reflect&#34;)
    (options, args) = parser.parse_args()

    main()

```

You will want to open up a terminal and start this up while we get the spring boot code working:

```bash
$ python2 reflect.py

```

## The Spring Boot App

To get this thing working in spring boot, we will need two different types of filters: A [WebClient filter](https://docs.spring.io/spring/docs/current/spring-framework-reference/web-reactive.html#webflux-client-filter) and a [spring boot webflux filter](https://docs.spring.io/spring/docs/current/spring-framework-reference/web-reactive.html#webflux-filters), which you can consider very similar to a servlet filter (but obviously it is reactive). First, let&#39;s configure the WebFlux filter:

```java
@Component
public class WebContextFilter implements WebFilter {

    public static final String X_CUSTOM_HEADER = &#34;X-Custom-Header&#34;;

    @Override
    public Mono&lt;Void&gt; filter(ServerWebExchange serverWebExchange, WebFilterChain webFilterChain) {
        List&lt;String&gt; customHeaderValues = serverWebExchange.getRequest().getHeaders().get(X_CUSTOM_HEADER);
        String singleCustomHeader = customHeaderValues != null &amp;&amp; customHeaderValues.size() == 1 ? customHeaderValues.get(0) : null;
        serverWebExchange.getResponse();
        return webFilterChain.filter(serverWebExchange).subscriberContext(context -&gt; {
            return singleCustomHeader != null ? context.put(X_CUSTOM_HEADER, new String[] {singleCustomHeader}) : context;
        });
    }
}

```

Forgive me for the excessive ternary operators. This piece of code, in a bit of a not obvious way, sets the subscriber context for everything _that comes before it_ in the chain. Though not super easy to understand, this is roughly the same thing as setting a ThreadLocal value just before the filter and clearing it just after the filter.

We can now introduce a WebClient filter to take advantage of this Context object:

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient webClient() {
        return WebClient.builder()
                .filter(new ExchangeFilterFunction() {
                    @Override
                    public Mono&lt;ClientResponse&gt; filter(ClientRequest clientRequest, ExchangeFunction exchangeFunction) {
                        return Mono.subscriberContext()
                                .flatMap(context -&gt; {
                                    String[] customHeader = context.get(X_CUSTOM_HEADER);
                                    ClientRequest clientReq = ClientRequest.from(clientRequest)
                                            .header(X_CUSTOM_HEADER, customHeader)
                                            .build();

                                    return exchangeFunction.exchange(clientReq);
                                });
                    }
                })
                .baseUrl(&#34;http://localhost:9000&#34;)
                .build();
    }
}

```

Here, we are assuming that there is one service downstream we need to talk to, and for the purposes of this tutorial I&#39;ve just hardcoded the location of this service to **http://localhost:9000**. As you can see, we&#39;re grabbing the subscriber context and pulling out our custom header, then cloning the **ClientRequest** and adding it to the request.

Finally, we can expose a hello-world like endpoint that will actually use this:

```java
@RestController
public class HelloController {

    private final WebClient webClient;

    public HelloController(WebClient webClient) {
        this.webClient = webClient;
    }

    @GetMapping(&#34;/hello&#34;)
    public Mono&lt;ResponseEntity&lt;String&gt;&gt; hello() {
        return Mono.subscriberContext()
                .flatMap(context -&gt; webClient.get()
                        .uri(&#34;/test&#34;)
                        .exchange()
                        .map(clientResponse -&gt; {
                            String[] strings = context.get(X_CUSTOM_HEADER);
                            return ResponseEntity.status(200)
                                    .header(X_CUSTOM_HEADER, strings)
                                    .build();
                        }));
    }
}

```

Also pretty straightforward, all this endpoint does is hit our downstream service, then responds with a 200 status code. For fun, I&#39;ve also echoed back the custom header that we&#39;re sending along.

If you start up this application and have the python echo server running above, you should be able to use a curl like this and see a similar output

```bash
$ curl -v -H &#34;X-Custom-Header: definitely-my-own-header&#34; localhost:8080/hello
*   Trying 127.0.0.1...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8080 (#0)
&gt; GET /hello HTTP/1.1
&gt; Host: localhost:8080
&gt; User-Agent: curl/7.58.0
&gt; Accept: */*
&gt; X-Custom-Header: definitely-my-own-header
&gt;
&lt; HTTP/1.1 200 OK
&lt; X-Custom-Header: definitely-my-own-header
&lt; content-length: 0
&lt;
* Connection #0 to host localhost left intact

```

You should be able to see the custom header in the response above, and we can go check our downstream server for it as well:

```bash
----- Request Start -----&gt;

/test
accept-encoding: gzip
user-agent: ReactorNetty/0.9.10.RELEASE
host: localhost:9000
accept: */*
X-Custom-Header: definitely-my-own-header

&lt;----- Request End -----

127.0.0.1 - - [26/Jul/2020 15:21:33] &#34;GET /test HTTP/1.1&#34; 200 -

```

Feel free to [check out the source code](https://github.com/nfisher23/reactive-programming-webflux/tree/master/context-api) for this one as well.
