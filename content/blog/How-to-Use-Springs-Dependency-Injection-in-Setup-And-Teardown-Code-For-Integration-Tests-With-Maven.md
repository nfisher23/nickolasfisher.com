---
title: "How to Use Spring's Dependency Injection in Setup And Teardown Code For Integration Tests With Maven"
date: 2018-11-24T15:51:32
draft: false
tags: [java, spring, DevOps, maven]
---

You can view the sample code for this repository [on GitHub](https://github.com/nfisher23/integration-testing-postgres-and-spring).

In our last post on [Using Maven to Setup and Teardown Integration Tests](https://nickolasfisher.com/blog/How-to-Run-Integration-Tests-with-Setup-and-Teardown-Code-in-Maven-Build), we saw how to run Java code before and after our integration tests to setup and teardown any data that our tests depended on. What if we are using Spring, and we want to use our ApplicationContext, and its dependency injection/property injection features? After all, we would be testing the configuration for our specific application more than anything else, so we should be certain to use it in our setup and teardown code.

To demonstrate, refer to my post on [setting up an unsecured local postgreSQL VM for testing purposes](https://nickolasfisher.com/blog/How-to-Set-Up-a-Local-Unsecured-Postgres-Virtual-Machine-for-testing). Assuming you have this vagrant VM up and running, we can create a simple bean for our data source and a JdbcTemplate like so:

```java
@Configuration
public class AppConfig {

    @Autowired
    Environment environment;

    @Bean
    public DataSource dataSource() {
        HikariDataSource ds = new HikariDataSource();

        ds.setJdbcUrl(environment.getProperty("spring.datasource.url"));
        ds.setUsername(environment.getProperty("spring.datasource.username"));
        ds.setPassword(environment.getProperty("spring.datasource.password"));
        ds.setDriverClassName(environment.getProperty("spring.datasource.driver-class-name"));

        return ds;
    }

    @Bean
    public JdbcTemplate jdbcTemplate(DataSource ds) {
        return new JdbcTemplate(ds);
    }
}
```

And we'll configure our datasource via the application.yml properties file in our resources folder:

```yaml
spring:
  datasource:
    password: postgres
    username: postgres
    url: jdbc:postgresql://192.168.56.111:5432/testdb
    driver-class-name: org.postgresql.Driver

```

Our integration test will run a query against a TMP\_TABLE table, and validate that we have two entries which are (1, "first") and (2, "second"):

```java
@RunWith(SpringRunner.class)
@SpringBootTest(classes = {AppConfig.class})
@ComponentScan(value = "com.nickolasfisher.postgresintegration")
public class PostgresAppIT {

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    public void validateQueryOnRealDB() {
        List<KeyValuePair> pairs = jdbcTemplate.query("SELECT mykey, myvalue FROM TMP_TABLE ORDER BY mykey asc", (rs, rowNum) ->
                new KeyValuePair(rs.getInt(1), rs.getString(2)));

        assertEquals("first", pairs.get(0).getValue());
        assertEquals(1, pairs.get(0).getKey().intValue());

        assertEquals(2, pairs.get(1).getKey().intValue());
        assertEquals("second", pairs.get(1).getValue());
    }

    private class KeyValuePair {

        private Integer key;
        private String value;

        public KeyValuePair(Integer key, String value) {
            this.key = key;
            this.value = value;
        }

        public String getValue() {
            return value;
        }

        public Integer getKey() {
            return key;
        }
    }
}

```

If we then want to set up and teardown our data for this test, we need to create the table if it doesn't exist, insert the appropriate data, then destroy the data or the table in our teardown environment. Thankfully, we can access the application context by getting the return value on SpringApplication.run(..) and getting any beans we want out of that:

```java
@ComponentScan("com.nickolasfisher.postgresintegration")
public class PreIntegrationSetup {

    public static void main(String args[]) {
        ConfigurableApplicationContext ctx = SpringApplication.run(PreIntegrationSetup.class, args);
        try {
            createTmpTable(ctx);
            insertTmpData(ctx);
        } catch (Exception e) {
            System.out.println("you blew up in your setup code: " + e.toString());
        }
        ctx.registerShutdownHook();
        ctx.close();
    }

    private static void createTmpTable(ApplicationContext ctx) {
        JdbcTemplate jdbcTemplate = ctx.getBean(JdbcTemplate.class);

        jdbcTemplate.update("CREATE TABLE TMP_TABLE (mykey INTEGER, myvalue text)");
    }

    private static void insertTmpData(ApplicationContext ctx) {
        JdbcTemplate jdbcTemplate = ctx.getBean(JdbcTemplate.class);

        jdbcTemplate.update("INSERT INTO TMP_TABLE (mykey, myvalue) VALUES (1, 'first')");
        jdbcTemplate.update("INSERT INTO TMP_TABLE (mykey, myvalue) VALUES (2, 'second')");
    }
}
```

And we can teardown our data, in this case I will choose to destroy the table completely from the test database, like:

```java
@ComponentScan("com.nickolasfisher.postgresintegration")
public class PostIntegrationTeardown {

    public static void main(String args[]) {
        ConfigurableApplicationContext ctx = SpringApplication.run(PostIntegrationTeardown.class, args);

        try {
            destroyTmpTable(ctx);
        } catch (Exception e) {
            System.out.println("you blew up in your teardown code: " + e.toString());
        }

        ctx.registerShutdownHook();
        ctx.close();
    }

    private static void destroyTmpTable(ApplicationContext ctx) {
        JdbcTemplate jdbcTemplate = ctx.getBean(JdbcTemplate.class);

        jdbcTemplate.update("DROP TABLE TMP_TABLE");
    }
}

```

Definitely go [download the source code](https://github.com/nfisher23/integration-testing-postgres-and-spring) to see and tinker with this in action.
