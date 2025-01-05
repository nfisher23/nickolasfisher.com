---
title: "How to Run Integration Tests with Setup and Teardown Code in Maven Build"
date: 2018-11-24T14:49:09
draft: false
tags: [java, DevOps, maven]
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/integration-testing-postgres-and-spring).

Unit testing with Maven is built in, and is the preferred way of validating code is performing correctly. However, sometimes you need integration testing, and most non-trivial applications built in the 21st century are reliant on network connections and databases--that is, things which are inherently third party to your application. If you don't adequately take that to account in your CI/CD pipeline, you might end up discovering that something very bad has happened after damage has already been done.

You can use the [maven failsafe plugin](https://maven.apache.org/surefire/maven-failsafe-plugin/) to do integration tests, but it's often the case that integration tests rely on data already existing somewhere--e.g. a third party service or in a database. We need a way to run code and ensure that our environment is set up correctly, then tear down anything that was created in that process, if we want a truly robust pipeline. What is useful about the failsafe plugin is that it guarantees that the phase before (pre-integration-test) and the phase after (post-integration-test) will get run regardless of what happens inside the integration-test phase.

To begin with, you should understand the [Maven Phase Lifecycle](https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html), in particular take a look at [The Complete Maven Phase Lifecycle](https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html#Lifecycle_Reference). First, we need to bind our integration tests, which should exist in a separate directory as our unit tests, to the integration-test phase. Update your pom to include this (in the build/plugins section):

```xml
            <!-- use the codehaus plugin to add a new test source, to keep unit and integration tests separated -->
            <plugin>
                <groupId>org.codehaus.mojo</groupId>
                <artifactId>build-helper-maven-plugin</artifactId>
                <executions>
                    <execution>
                        <id>add-test-source</id>
                        <phase>process-resources</phase>
                        <goals>
                            <goal>add-test-source</goal>
                        </goals>
                        <configuration>
                            <sources>
                                <source>src/testintegration/java/com/nickolasfisher/postgresintegration/tests</source>
                            </sources>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
```

We will then assume any integration tests will end in IT, and add this section to the pom as well. Here I'll assume your integration tests are in the **src/testintegration/java/com/nickolasfisher/postgresintegration/tests** directory:

```xml
            <!-- the failsafe plugin runs our integration tests. By convention, we will consider every class ending in IT an integration test module-->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-failsafe-plugin</artifactId>
                <configuration>
                    <includes>
                        <include>**/*IT</include>
                    </includes>
                </configuration>
                <executions>
                    <execution>
                        <id>integration-testing</id>
                        <goals>
                            <goal>integration-test</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>run-verify</id>
                        <goals>
                            <goal>verify</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
```

If we then have an integration test in the appropriate folder like:

```java
public class PostgresAppIT {

    @Test
    public void simpleIntegrationTest() {
        System.out.println("integration test");
        assertTrue(true);
    }
}

```

Then run

```bash
$ mvn verify
```

You will see the integration tests run separately from the unit tests, and in particular it will run during the integration-test phase.

Now we need a way to execute code in the pre-integration-test and post-integration-test phase. We can use another org.codehaus plugin, the [exec-maven-plugin](https://www.mojohaus.org/exec-maven-plugin/), to accomplish that. First we have to add sources, and here I'll assume your pre and post integration test code will reside in **src/testintegration/java/com/nickolasfisher/postgresintegration/setup** and **src/testintegration/java/com/nickolasfisher/postgresintegration/teardown**, respectively. We can update our build helper add sources section to look like:

```xml
            <plugin>
                <groupId>org.codehaus.mojo</groupId>
                <artifactId>build-helper-maven-plugin</artifactId>
                <executions>
                    <execution>
                        <id>add-test-source</id>
                        <phase>process-resources</phase>
                        <goals>
                            <goal>add-test-source</goal>
                        </goals>
                        <configuration>
                            <sources>
                                <source>src/testintegration/java/com/nickolasfisher/postgresintegration/tests</source>
                            </sources>
                        </configuration>
                    </execution>
                    <execution>
                        <phase>process-resources</phase>
                        <goals>
                            <goal>add-source</goal>
                        </goals>
                        <configuration>
                            <sources>
                                <source>src/testintegration/java/com/nickolasfisher/postgresintegration/setup</source>
                                <source>src/testintegration/java/com/nickolasfisher/postgresintegration/teardown</source>
                            </sources>
                        </configuration>
                    </execution>
                </executions>
            </plugin>

```

And we can create PreIntegrationTest and PostIntegrationTest classes to run arbitrary Java code like:

```java
public class PreIntegrationSetup {

    public static void main(String args[]) {
        System.out.println("executing set up tasks!");
    }
}

```

And:

```java
public class PostIntegrationTeardown {

    public static void main(String args[]) {
        System.out.println("executing teardown code!");
    }
}
```

Finally, we can update our pom file to include the exec-maven-plugin referenced above:

```xml
            <plugin>
                <groupId>org.codehaus.mojo</groupId>
                <artifactId>exec-maven-plugin</artifactId>
                <executions>
                    <execution>
                        <id>pre-integration-test</id>
                        <phase>pre-integration-test</phase>
                        <goals>
                            <goal>java</goal>
                        </goals>
                        <configuration>
                            <mainClass>PreIntegrationSetup</mainClass>
                        </configuration>
                    </execution>
                    <execution>
                        <id>post-integration-test</id>
                        <phase>post-integration-test</phase>
                        <goals>
                            <goal>java</goal>
                        </goals>
                        <configuration>
                            <mainClass>PostIntegrationTeardown</mainClass>
                        </configuration>
                    </execution>
                </executions>
            </plugin>

```

[Go get the source code](https://github.com/nfisher23/integration-testing-postgres-and-spring) and checkout the correct commit (991015831dd71bae58c8a045ffe76c390e9f2bf8) to see this in action.

Finally, if you're using Spring, there is a way to [use Spring's ApplicationContext in your setup and teardown code](https://nickolasfisher.com/blog/how-to-use-springs-dependency-injection-in-setup-and-teardown-code-for-integration-tests-with-maven), which is a much more maintable way to ensure everything fits correctly together.
