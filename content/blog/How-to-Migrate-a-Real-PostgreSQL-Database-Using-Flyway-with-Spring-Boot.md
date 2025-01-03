---
title: "How to Migrate a Real PostgreSQL Database Using Flyway with Spring Boot"
date: 2019-04-20T16:37:18
draft: false
tags: [java, distributed systems, vagrant, spring, DevOps, postgreSQL]
---

You can see the source code for this post [on GitHub](https://github.com/nfisher23/postgres-flyway-example).

We spent the last post figuring out [how to migrate an embedded PostgreSQL database using Spring](https://nickolasfisher.com/blog/How-to-Migrate-An-Embedded-PostgreSQL-Database-Using-Flyway-in-Spring-Boot), while trying to side-step the extra magic that comes along with the framework. Here, we are going to build on that work to migrate a real PostgreSQL instance, which we will build in a local Vagrant Virtual Machine.

To do this in a maintainable way, we will want to leverage [Spring Profiles](https://docs.spring.io/spring-boot/docs/current/reference/html/boot-features-profiles.html) to allow us to retain local development as an option and switch to another setup relatively quickly. We will change our **application.yml** file to look like:

```yaml
spring.profiles.active: dev

---
spring.profiles: dev
spring.flyway.enabled: false

---
spring.profiles: stage
spring.flyway.enabled: false
spring.datasource.password: postgres
spring.datasource.username: postgres
spring.datasource.url: jdbc:postgresql://192.168.56.111:5432/testdb
spring.datasource.driver-class-name: org.postgresql.Driver
```

Here, we are telling Spring Boot to use the &#34;dev&#34; profile by default, and if we decide to use the &#34;stage&#34; profile, then the application will attempt to connect to a PostgreSQL database at the 192.168.56.111 IP address, at port 5432. It will connect to the **testdb** database and use postgres/postgres as the username/password combo.

**Note**: Never use postgres/postgres as the username/password combo for a database that you actually want to protect. This will last about five seconds on the internet.

With the work we have already done, this will ensure that our application runs the database migration scripts on application start time in an idempotent way. We just need a real database to validate this against, and I will use [Vagrant](https://www.vagrantup.com/). I&#39;ve created a **postgres-vm/Vagrantfile** like:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;ubuntu/bionic64&#34;

  config.vm.provider &#34;virtualbox&#34; do |v|
    v.memory = 2048
    v.cpus = 1
  end

  config.vm.provision &#34;file&#34;, source: &#34;~/.ssh/id_rsa.pub&#34;, destination: &#34;~/.ssh/me.pub&#34;
  config.vm.provision &#34;shell&#34;, inline: &#34;cat /home/vagrant/.ssh/me.pub &gt;&gt; /home/vagrant/.ssh/authorized_keys&#34;
  config.vm.provision &#34;shell&#34;, inline: &#34;mkdir -p /root &amp;&amp; mkdir -p /root/.ssh/ &amp;&amp; cat /home/vagrant/.ssh/me.pub &gt;&gt; /root/.ssh/authorized_keys&#34;
  config.vm.provision :shell, path: &#34;postgres-provision.sh&#34;
  config.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.111&#34;
end
```

This Vagrantfile needs a **postgres-provision.sh** bash script in the same directory, which looks like this:

```bash
#!/bin/bash

sudo apt-get update &amp;&amp; sudo apt-get -y install postgresql

# set the default to listen to all addresses
sudo sed -i &#34;/port*/a listen_addresses = &#39;*&#39;&#34; /etc/postgresql/10/main/postgresql.conf

# allow any authentication mechanism from any client
sudo sed -i &#34;$ a host all all all trust&#34; /etc/postgresql/10/main/pg_hba.conf

# create db named testdb
sudo su postgres -c &#34;createdb testdb&#34;

# restart the service to allow changes to take effect
sudo service postgresql restart

```

This creates a PostgreSQL database and exposes it (with no security) to the outside world, which in this case is just our local development environment.

Do:

```bash
$ cd postgres-vm
$ vagrant up
```

And, once the VM is up and running, you can:

```bash
$ cd ..
$ mvn clean install
$ SPRING_PROFILES_ACTIVE=stage java -jar target/flywaystuff-1.0.jar
```

The application will come up and connect to our local database at this point. You can verify that the migration ran properly with:

```bash
$ cd ../postgres-vm
$ vagrant ssh
$ sudo -i -u postgres
$ psql -d testdb
testdb=# \dt
```

You should get an output like this:

```
                 List of relations
 Schema |         Name          | Type  |  Owner
--------&#43;-----------------------&#43;-------&#43;----------
 public | employee              | table | postgres
 public | flyway_schema_history | table | postgres
(2 rows)
```

And we have done it successfully.
