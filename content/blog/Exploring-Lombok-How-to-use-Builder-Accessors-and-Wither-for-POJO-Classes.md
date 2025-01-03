---
title: "Exploring Lombok: How to use @Builder, @Accessors, and @Wither for POJO Classes"
date: 2019-02-09T15:50:55
draft: false
---

[Lombok](https://projectlombok.org/) manipulates the output java bytecode .class files, and inserts boilerplate code that java developers are very familiar with repeating themselves on.

This post will address three wonderful features of Lombok: @Buidler, @Accessors, and @Wither.

### @Builder

The Builder annotation is based off of the popular design pattern from Effective Java. Combine @Builder with @Getter and you can make a read only class that cannot be modified after construction. If all of the types within the class are immutable, then the class itself is immutable. Immutable objects are a lot easier to work with, particularly in concurrent programming.

This:

```java
@Builder
public class Person {
    private String firstName;
    private String lastName;
    private int height;
}
```

Can be called anywhere in the code like so:

```java
Person person = Person.builder()
                .firstName(&#34;Jack&#34;)
                .lastName(&#34;Bauer&#34;)
                .height(100)
                .build();

```

But in practice this isn&#39;t particularly helpful. Typically this is combined with @Getter to access an immutable object after building it:

```java
@Builder
@Getter
public class Person {
    private String firstName;
    private String lastName;
    private int height;
}
```

Which can then be very practically applied like so:

```java
    @Test
    public void testBuilder() {
        Person person = Person.builder()
                .firstName(&#34;Jack&#34;)
                .lastName(&#34;Bauer&#34;)
                .height(100)
                .build();

        assertEquals(&#34;Jack&#34;, person.getFirstName());
        assertEquals(&#34;Bauer&#34;, person.getLastName());
        assertEquals(100, person.getHeight());
    }
```

### @Accessors

The [accessors](https://projectlombok.org/features/experimental/Accessors) annotation is currently an &#34;experimental&#34; feature. The most powerful feature puts it in a similar camp to @Builder, which is it&#39;s **chain** option. This adjusts the behavior of setters to return **this** after setting the value, making modifications to existing objects more compact:

```java
@Accessors(chain = true)
@Setter @Getter
public class Person {
    private String firstName;
    private String lastName;
    private int height;
}

....

@Test
public void testAccessors() {
    Person person = new Person();

    person.setFirstName(&#34;Jack&#34;)
        .setLastName(&#34;Bauer&#34;)
        .setHeight(100);

    assertEquals(&#34;Jack&#34;, person.getFirstName());
    assertEquals(&#34;Bauer&#34;, person.getLastName());
    assertEquals(100, person.getHeight());
}

```

This usage implies that the object is mutable, but still has valid use cases from where I sit.

### @Wither

The [wither](https://projectlombok.org/features/experimental/Wither) annotation is also experimental, with a less favorable current view than accessors by the community. We use Wither exclusively on a field, at the moment, and when we use it in code it returns a **clone** of the object, with the only modified field being the field called by .with\*\*\*(..). If we add a **@Wither** to our Person:

```java
@Builder
@Getter
public class Person {

    @Wither
    private String firstName;

    private String lastName;

    private int height;
}

```

We can then see that it properly clones the object like so:

```java
@Test
public void testWither() {
    Person person = Person.builder()
            .firstName(&#34;Jack&#34;)
            .lastName(&#34;Bauer&#34;)
            .height(100)
            .build();

    Person clonedPerson = person.withFirstName(&#34;Joe&#34;);

    assertEquals(&#34;Jack&#34;, person.getFirstName());
    assertEquals(&#34;Joe&#34;, clonedPerson.getFirstName());
}

```

This is another very useful annotation in concurrent programming. If you have a set of data that is far more often read than it is written, then the above immutable and easily clone-able Person is thread safe.
