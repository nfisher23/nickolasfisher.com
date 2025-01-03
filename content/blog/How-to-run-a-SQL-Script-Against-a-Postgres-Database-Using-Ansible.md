---
title: "How to run a SQL Script Against a Postgres Database Using Ansible"
date: 2019-02-09T15:44:26
draft: false
tags: [ansible, DevOps, postgreSQL]
---

The source code for this post can be found [on GitHub](https://github.com/nfisher23/run-sql-ansible-postgres).

Managing a live database, and in particular dealing with database migrations without allowing for any downtime in your application, is typically the most challenging part of any automated deployment strategy. Services can be spun up and down with impunity because their state at the beginning and at the end are exactly the same, but databases store data--their state is always changing.

From where I sit, there are two good options for dealing with database migrations: at an application level (e.g. a startup script when you connect with a service) or using a tool like Ansible. Either one of them allow you to write automation for the migrations, which is (in my opinion) non-negotiable for maintaining any non-trivial software project. While I lean towards the application owning the migrations, Ansible or another idempotent management tool is a somewhat close second, and may be better for your use case.

There are a few different ways to run a SQL script against Postgres using Ansible. The first is to take a sql file and dump it on the server you're managing, then run the sql script using a psql command. First we'll install Postgres for a Debian distribution with apt:

```yaml
---
# tasks file for run-sql-postgres
- name: install postgres
  apt:
    update_cache: yes
    name: ['postgresql', 'postgresql-contrib']
    state: present
```

Next I'll create a testing database to run the scripts against with the built in postgresql\_db ansible module:

```yaml
- name: ensure psycopg2
  apt:
    name: python-psycopg2

- name: ensure testing database created
  postgresql_db:
    name: testdb # required. name of the database to add or remove
  become_user: postgres

```

In our ansible role directory, we'll create a **files/migrate.sql** file with the following contents:

```sql
CREATE TABLE IF NOT EXISTS products (
    product_id serial PRIMARY KEY,
    name varchar(100),
    price numeric
);

```

With the file in place, we can return to our **tasks/main.yml** file and add a first example:

```yaml
# first method
- name: dump a database file
  copy:
    dest: /etc/migrate.sql
    src: migrate.sql
  register: sql_file_path

- name: run custom sql script
  command: "psql testdb -f {{ sql_file_path.dest }}"
  become_user: postgres
  register: sql_response_file

- name: debug response
  debug:
    var: sql_response_file

```

This sends the file to **/etc/migrate.sql**, then uses the command module to run psql with the **-f** option for files. You can run it yourself and see the type of response that you're getting. With this method, it will **always** report the "run custom sql script" task as **changed**. You can optionally choose to modify that behavior with the changed\_when option.

The second method will read the file into a variable, then use the variable to run psql with the **-c** option for command:

```yaml
# second method
- name: load sql into variable
  set_fact:
    migrate_sql: "{{ lookup('file', 'migrate.sql') }}"

- name: debug variable
  debug:
    var: migrate_sql

- name: run custom script from variable
  command: psql testdb -c "{{ migrate_sql }}"
  become_user: postgres
  register: sql_response_variable

- name:
  debug:
    var: sql_response_variable

```

In both cases, the variables will report a virtually identical output.
