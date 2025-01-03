---
title: "How to Run Integration Tests with Setup and Teardown Code in Maven Build"
date: 2018-11-24T14:49:09
draft: false
tags: [java, DevOps, maven]
---

The sample code for this post can be found [on GitHub](https://github.com/nfisher23/integration-testing-postgres-and-spring).

Unit testing with Maven is built in, and is the preferred way of validating code is performing correctly. However, sometimes you need integration testing, and most non-trivial applications built in the 21st century are reliant on network connections and databases--that is, things which are inherently third party to your application. If you don&#39;t adequately take that to account in your CI/CD pipeline, you might end up discovering that something very bad has happened after damage has already been done.

You can use the [maven failsafe plugin](https://maven.apache.org/surefire/maven-failsafe-plugin/) to do integration tests, but it&#39;s often the case that integration tests rely on data already existing somewhere--e.g. a third party service or in a database. We need a way to run code and ensure that our environment is set up correctly, then tear down anything that was created in that process, if we want a truly robust pipeline. What is useful about the failsafe plugin is that it guarantees that the phase before (pre-integration-test) and the phase after (post-integration-test) will get run regardless of what happens inside the integration-test phase.

To begin with, you should understand the [Maven Phase Lifecycle](https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html), in particular take a look at [The Complete Maven Phase Lifecycle](https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html#Lifecycle_Reference). First, we need to bind our integration tests, which should exist in a separate directory as our unit tests, to the integration-test phase. Update your pom to include this (in the build/plugins section):

```xml
            &lt;!-- use the codehaus plugin to add a new test source, to keep unit and integration tests separated --&gt;
            &lt;plugin&gt;
                &lt;groupId&gt;org.codehaus.mojo&lt;/groupId&gt;
                &lt;artifactId&gt;build-helper-maven-plugin&lt;/artifactId&gt;
                &lt;executions&gt;
                    &lt;execution&gt;
                        &lt;id&gt;add-test-source&lt;/id&gt;
                        &lt;phase&gt;process-resources&lt;/phase&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;add-test-source&lt;/goal&gt;
                        &lt;/goals&gt;
                        &lt;configuration&gt;
                            &lt;sources&gt;
                                &lt;source&gt;src/testintegration/java/com/nickolasfisher/postgresintegration/tests&lt;/source&gt;
                            &lt;/sources&gt;
                        &lt;/configuration&gt;
                    &lt;/execution&gt;
                &lt;/executions&gt;
            &lt;/plugin&gt;
```

We will then assume any integration tests will end in IT, and add this section to the pom as well. Here I&#39;ll assume your integration tests are in the **src/testintegration/java/com/nickolasfisher/postgresintegration/tests** directory:

```xml
            &lt;!-- the failsafe plugin runs our integration tests. By convention, we will consider every class ending in IT an integration test module--&gt;
            &lt;plugin&gt;
                &lt;groupId&gt;org.apache.maven.plugins&lt;/groupId&gt;
                &lt;artifactId&gt;maven-failsafe-plugin&lt;/artifactId&gt;
                &lt;configuration&gt;
                    &lt;includes&gt;
                        &lt;include&gt;**/*IT&lt;/include&gt;
                    &lt;/includes&gt;
                &lt;/configuration&gt;
                &lt;executions&gt;
                    &lt;execution&gt;
                        &lt;id&gt;integration-testing&lt;/id&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;integration-test&lt;/goal&gt;
                        &lt;/goals&gt;
                    &lt;/execution&gt;
                    &lt;execution&gt;
                        &lt;id&gt;run-verify&lt;/id&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;verify&lt;/goal&gt;
                        &lt;/goals&gt;
                    &lt;/execution&gt;
                &lt;/executions&gt;
            &lt;/plugin&gt;
```

If we then have an integration test in the appropriate folder like:

```java
public class PostgresAppIT {

    @Test
    public void simpleIntegrationTest() {
        System.out.println(&#34;integration test&#34;);
        assertTrue(true);
    }
}

```

Then run

```bash
$ mvn verify
```

You will see the integration tests run separately from the unit tests, and in particular it will run during the integration-test phase.

Now we need a way to execute code in the pre-integration-test and post-integration-test phase. We can use another org.codehaus plugin, the [exec-maven-plugin](https://www.mojohaus.org/exec-maven-plugin/), to accomplish that. First we have to add sources, and here I&#39;ll assume your pre and post integration test code will reside in **src/testintegration/java/com/nickolasfisher/postgresintegration/setup** and **src/testintegration/java/com/nickolasfisher/postgresintegration/teardown**, respectively. We can update our build helper add sources section to look like:

```xml
            &lt;plugin&gt;
                &lt;groupId&gt;org.codehaus.mojo&lt;/groupId&gt;
                &lt;artifactId&gt;build-helper-maven-plugin&lt;/artifactId&gt;
                &lt;executions&gt;
                    &lt;execution&gt;
                        &lt;id&gt;add-test-source&lt;/id&gt;
                        &lt;phase&gt;process-resources&lt;/phase&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;add-test-source&lt;/goal&gt;
                        &lt;/goals&gt;
                        &lt;configuration&gt;
                            &lt;sources&gt;
                                &lt;source&gt;src/testintegration/java/com/nickolasfisher/postgresintegration/tests&lt;/source&gt;
                            &lt;/sources&gt;
                        &lt;/configuration&gt;
                    &lt;/execution&gt;
                    &lt;execution&gt;
                        &lt;phase&gt;process-resources&lt;/phase&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;add-source&lt;/goal&gt;
                        &lt;/goals&gt;
                        &lt;configuration&gt;
                            &lt;sources&gt;
                                &lt;source&gt;src/testintegration/java/com/nickolasfisher/postgresintegration/setup&lt;/source&gt;
                                &lt;source&gt;src/testintegration/java/com/nickolasfisher/postgresintegration/teardown&lt;/source&gt;
                            &lt;/sources&gt;
                        &lt;/configuration&gt;
                    &lt;/execution&gt;
                &lt;/executions&gt;
            &lt;/plugin&gt;

```

And we can create PreIntegrationTest and PostIntegrationTest classes to run arbitrary Java code like:

```java
public class PreIntegrationSetup {

    public static void main(String args[]) {
        System.out.println(&#34;executing set up tasks!&#34;);
    }
}

```

And:

```java
public class PostIntegrationTeardown {

    public static void main(String args[]) {
        System.out.println(&#34;executing teardown code!&#34;);
    }
}
```

Finally, we can update our pom file to include the exec-maven-plugin referenced above:

```xml
            &lt;plugin&gt;
                &lt;groupId&gt;org.codehaus.mojo&lt;/groupId&gt;
                &lt;artifactId&gt;exec-maven-plugin&lt;/artifactId&gt;
                &lt;executions&gt;
                    &lt;execution&gt;
                        &lt;id&gt;pre-integration-test&lt;/id&gt;
                        &lt;phase&gt;pre-integration-test&lt;/phase&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;java&lt;/goal&gt;
                        &lt;/goals&gt;
                        &lt;configuration&gt;
                            &lt;mainClass&gt;PreIntegrationSetup&lt;/mainClass&gt;
                        &lt;/configuration&gt;
                    &lt;/execution&gt;
                    &lt;execution&gt;
                        &lt;id&gt;post-integration-test&lt;/id&gt;
                        &lt;phase&gt;post-integration-test&lt;/phase&gt;
                        &lt;goals&gt;
                            &lt;goal&gt;java&lt;/goal&gt;
                        &lt;/goals&gt;
                        &lt;configuration&gt;
                            &lt;mainClass&gt;PostIntegrationTeardown&lt;/mainClass&gt;
                        &lt;/configuration&gt;
                    &lt;/execution&gt;
                &lt;/executions&gt;
            &lt;/plugin&gt;

```

[Go get the source code](https://github.com/nfisher23/integration-testing-postgres-and-spring) and checkout the correct commit (991015831dd71bae58c8a045ffe76c390e9f2bf8) to see this in action.

Finally, if you&#39;re using Spring, there is a way to [use Spring&#39;s ApplicationContext in your setup and teardown code](https://nickolasfisher.com/blog/How-to-Use-Springs-Dependency-Injection-in-Setup-And-Teardown-Code-For-Integration-Tests-With-Maven), which is a much more maintable way to ensure everything fits correctly together.
