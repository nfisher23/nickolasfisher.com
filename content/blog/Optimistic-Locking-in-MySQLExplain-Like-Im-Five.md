---
title: "Optimistic Locking in MySQL--Explain Like I&#39;m Five"
date: 2020-07-01T00:00:00
draft: false
---

Optimistic Locking is a compromise to improve performance. If processors were infinitely fast, we wouldn&#39;t need it and it would add unnecessary complexity. But, well, they aren&#39;t.

Optimistic Locking was also introduced because holding open locks on databases can cause cascading failures, bubbling up unnecessary errors to users.

So what is it? It&#39;s not locking at all, it&#39;s just another form of concurrency control that takes some load off of the database. You try to update a record based off some known property of the row (typically a version or datetime field) that you read as a select query at the start of a transaction. Let&#39;s set up the example with MySQL:

#### 1\. Start a MySQL database \[I&#39;m using docker, obviously\]:

``` bash
$ docker container run --env &#34;MYSQL_ALLOW_EMPTY_PASSWORD=true&#34; -d -p 3306:3306 mysql

```

#### 2\. Setup test data

``` bash
$ mysql --protocol tcp -u root
CREATE SCHEMA IF NOT EXISTS myschema;

use myschema;

CREATE TABLE mytable (
    prim_key INT AUTO_INCREMENT PRIMARY KEY,
    first_column VARCHAR(50),
    second_column VARCHAR(100),
    version INT DEFAULT 1
);

INSERT INTO mytable ( first_column, second_column )
VALUES
( &#39;jack&#39;, &#39;bauer&#39;);

```

#### 3\. Actual Example and Explanation Now

Open two different terminals, I&#39;ll call them **T1** and **T2** and start typing in the order specified by the comments:

``` bash
#### T1
$ mysql --protocol tcp - u root
USE myschema;

START TRANSACTION;

SELECT * FROM mytable where prim_key = 1;

#### T2
$ mysql --protocol tcp -u root
USE myschema;

START TRANSACTION;

SELECT * FROM mytable where prim_key = 1;

```

Notice that T2 did not block, even though we&#39;re in a transaction. What does this mean? It means that the remainder of each transaction is made with an assumption about how the data was at the start of the transaction. If both threads start marching forward and want to update that data without optimistic locking, then one will be overwriting the other one:

``` bash
#### T1 - DON&#39;T ACTUALLY EXECUTE THIS
UPDATE mytable SET second_column = &#39;jackson&#39; where prim_key = 1;

COMMIT;

#### T2 - DON&#39;T ACTUALLY EXECUTE THIS
UPDATE mytable SET second_column = &#39;johnson&#39; where prim_key = 1;

COMMIT;

```

Depending on the order of these two distinct transactions, one is going to be overwriting the other without knowing that the data had changed midway through--the second\_column could be either &#34;jackson&#34; or &#34;johnson&#34;. There are some use cases where this isn&#39;t that big of a deal and many others where it is _definitely a big deal_, especially if the engineer writing the application doesn&#39;t understand that this is going to happen.

#### Optimistic Locking - A Practice, not a Database Feature

Optimistic Locking &#34;fixes&#34; this problem by observing some attribute about the data that it is changing, and if that value has changed the code will roll back the transaction. This can be made atomic in two ways: first, MySQL will hold open a lock on data that is being UPDATED (not selected, by default), and second, include the piece of data in the actual update as a WHERE condition, so that if the operation fails we can see the number of rows that were updated. If the number of rows that were updated is zero, then it&#39;s an optimistic locking exception and we should roll back:

``` bash
#### T1 - Pay attention to the output
UPDATE mytable SET second_column = &#39;jackson&#39; where prim_key = 1;

