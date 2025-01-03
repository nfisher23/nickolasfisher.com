---
title: "How to Dynamically Deserialize JSON In Java With Jackson"
date: 2018-11-01T00:00:00
draft: false
---

You can find the sample code associated with this blog post [on GitHub](https://github.com/nfisher23/json-with-jackson-tricks).

[Jackson](https://github.com/FasterXML/jackson) is a data processor in Java, known particularly well for its ability to deal with JSON payloads.

Java is a statically typed language, whose types must be known at compile time. Conversely, dynamically typed languages are the wild wild west--we can, and often do, decide to let any variable be whatever it wants to be at runtime. This is the inherent problem between JSON and Java--JavaScript is dynamic, Java is static. So, when we get a JSON payload like:

``` json
{
    &#34;hasErrors&#34;: false,
    &#34;body&#34;: {
        &#34;property1&#34;: &#34;value1&#34;,
        &#34;property2&#34;: &#34;value2&#34;
    }
}
```

We can make a POJO to deserialize pretty easily, like:

``` java
public class ResponseObject {

    @JsonProperty(&#34;hasErrors&#34;)
    private boolean hasErrors;

    @JsonProperty(&#34;body&#34;)
    private SimpleObject body;
}

... in a different file ...

public class SimpleObject {

    @JsonProperty(&#34;property1&#34;)
    private String property1;

    @JsonProperty(&#34;property2&#34;)
    private String property2;

    public String getProperty1() {
        return property1;
    }

    public String getProperty2() {
        return property2;
    }
}
```

And this will deserialize with a call to ObjectMapper.readValue(json, ResponseObject.class).

However, what if the same service also has a response like:

``` json
{
    &#34;hasErrors&#34;: true,
    &#34;body&#34;: [
        {
            &#34;errorMessage&#34;: &#34;you totally messed this up&#34;
        },
        {
            &#34;errorMessage&#34;: &#34;seriously, that was pretty whack&#34;
        }
    ]
}

```

In Java, since we have defined the body to be an object, trying to deserialize into the previously defined objects above will blow everything up. This would be easy to take care of in JavaScript or another dynamic language like Python, but Java requires us to get a little creative. In this very specific case, we could technically create another object and wrap each deserialization attempt in a try/catch block. However, sometimes we get back an array of objects, where each object could be either of the responses shown above, and then we have to put our spectacles on and figure something else out.

Jackson defaults to defining each node in the JSON object structure as a JsonNode. So, if we want to be able to handle multiple types of bodies (both arrays and objects, for example), we can simply defer the deserialization into a Java class until after we&#39;ve had a chance to process it. We can then define another POJO as:

``` java
public class DynamicResponseObject {

    @JsonProperty(&#34;hasErrors&#34;)
    private boolean hasErrors;

    @JsonIgnore
    private JsonNode bodyAsNode;

    @JsonProperty(&#34;body&#34;)
    private void setBody(JsonNode body) {
        this.bodyAsNode = body;
    }

    public JsonNode getBodyAsNode() {
        return this.bodyAsNode;
    }
}

```

And we can access the actual properties of our node underneath with a myriad of [methods for JsonNode](https://fasterxml.github.io/jackson-databind/javadoc/2.7/com/fasterxml/jackson/databind/JsonNode.html). For example, if we want to see whether the body is an array or object, we can call isArray() or isObject():

``` java
@RunWith(SpringRunner.class)
@SpringBootTest
public class DynamicDeserializationApplicationTests {

    @Autowired
    ObjectMapper objectMapper;

    public static final String NORMAL_RESPONSE = &#34;{\&#34;hasErrors\&#34;:false,\&#34;body\&#34;:{\&#34;property1\&#34;:\&#34;value1\&#34;,\&#34;property2\&#34;:\&#34;value2\&#34;}}&#34;;
    public static final String RESPONSE_WITH_ERRORS = &#34;{\&#34;hasErrors\&#34;:true,\&#34;body\&#34;:[{\&#34;errorMessage\&#34;:\&#34;you totally messed this up\&#34;},{\&#34;errorMessage\&#34;:\&#34;seriously, that was pretty whack\&#34;}]}&#34;;

    @Test
    public void normalResponse_setsBodyIsObject() throws Exception {
        DynamicResponseObject dynamicResponseObject = objectMapper.readValue(NORMAL_RESPONSE, DynamicResponseObject.class);

        assertTrue(dynamicResponseObject.getBodyAsNode().isObject());
    }

    @Test
    public void abnormalResponse_setsBodyIsArray() throws Exception {
        DynamicResponseObject dynamicResponseObject = objectMapper.readValue(RESPONSE_WITH_ERRORS, DynamicResponseObject.class);

        assertTrue(dynamicResponseObject.getBodyAsNode().isArray());
    }
}

```

If we want to see the properties of something we know is an object, we can call get(..) and transform it into whatever we think the type is (here using asText() to get it as a String):

``` java
    @Test
    public void normalResponse_accessNodeDynamically() throws Exception {
        DynamicResponseObject dynamicResponseObject = objectMapper.readValue(NORMAL_RESPONSE, DynamicResponseObject.class);

        JsonNode bodyNode = dynamicResponseObject.getBodyAsNode();

        assertEquals(&#34;value1&#34;, bodyNode.get(&#34;property1&#34;).asText());
        assertEquals(&#34;value2&#34;, bodyNode.get(&#34;property2&#34;).asText());
    }

```

We can see the array properties by using get(..) with an int argument:

``` java
    @Test
    public void abnormalResponse_accessNodesDynamically() throws Exception {
        DynamicResponseObject dynamicResponseObject = objectMapper.readValue(RESPONSE_WITH_ERRORS, DynamicResponseObject.class);

        JsonNode bodyNode = dynamicResponseObject.getBodyAsNode();

        assertEquals(&#34;you totally messed this up&#34;, bodyNode.get(0).get(&#34;errorMessage&#34;).asText());
        assertEquals(&#34;seriously, that was pretty whack&#34;, bodyNode.get(1).get(&#34;errorMessage&#34;).asText());
    }

```

Now, if we want to take it a step further and deserialize into a Java object, which has the obvious advantage of being compile-time safe (provided it deserializes correctly from the API) and providing Intellisense to developers, we will have to get a little creative. We can use an ObjectMapper to deserialize the node as a String like:

``` java
    @JsonIgnore
    private SimpleObject simpleObject;

    public SimpleObject getBodyAsSimpleObject() throws IOException {
        if (simpleObject == null) {
            setSimpleObject();
        }
        return simpleObject;
    }

    private void setSimpleObject() throws IOException {
        if (bodyAsNode.isObject()) {
            simpleObject = objectMapper.readValue(bodyAsNode.toString(), SimpleObject.class);
        } else {
            simpleObject = new SimpleObject();
        }
    }

```

And we can similarly define an error class:

``` java
public class Error {

    @JsonProperty(&#34;errorMessage&#34;)
    private String errorMessage;

    public String getErrorMessage() {
        return errorMessage;
    }
}

```

And then deserialize it like:

``` java
    @JsonIgnore
    private List&lt;Error&gt; errors;

    public List&lt;Error&gt; getErrors() throws IOException {
        if (errors == null) {
            setErrors();
        }
        return errors;
    }

    private void setErrors() throws IOException {
        if (bodyAsNode.isArray()) {
            TypeFactory typeFactory = objectMapper.getTypeFactory();
            JavaType javaType = typeFactory.constructParametricType(List.class, Error.class);
            errors = objectMapper.readValue(bodyAsNode.toString(), javaType);
        } else {
            errors = new ArrayList&lt;&gt;();
        }
    }

```

Keep in mind that we can&#39;t inject an ObjectMapper into this POJO class because it gets deserialized, and not created by a DI framework (like, for example, Spring). It would be smart to not instantiate a new ObjectMapper in the class itself, since the benefits of dependency injection are pretty obvious at this point. If you are using Spring, you can ask for a previously defined ObjectMapper by leveraging the ApplicationContext. Create an ApplicationContextProvider like:

``` java
@Component
public class ApplicationContextProvider implements ApplicationContextAware {

    private static ApplicationContext applicationContext;

    public static ApplicationContext getApplicationContext() {
        return applicationContext;
    }

    @Override
    public void setApplicationContext(ApplicationContext appContext) throws BeansException {
        applicationContext = appContext;
    }
}

```

And then get a bit of a hacked DI result by calling it inside your POJO:

``` java
    @JsonIgnore
    ObjectMapper objectMapper = ApplicationContextProvider.getApplicationContext().getBean(ObjectMapper.class);

```

Which is still kind of ugly, but at least reduces the cost of instantiation duplication.

Definitely [download the source code for this post](https://github.com/nfisher23/json-with-jackson-tricks) and play around with it if it&#39;s not clear to you.


