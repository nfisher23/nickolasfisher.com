---
title: "Optimistic Locking in MySQL--Explain Like I'm Five"
date: 2020-07-26T00:00:56
draft: false
tags: []
---

Optimistic Locking is a compromise to improve performance. If processors were infinitely fast, we wouldn't need it and it would add unnecessary complexity. But, well, they aren't.

Optimistic Locking was also introduced because holding open locks on databases can cause cascading failures, bubbling up unnecessary errors to users.

So what is it? It's not locking at all, it's just another form of concurrency control that takes some load off of the database. You try to update a record based off some known property of the row (typically a version or datetime field) that you read as a select query at the start of a transaction. Let's set up the example with MySQL:

#### 1\. Start a MySQL database \[I'm using docker, obviously\]:

```bash
$ docker container run --env "MYSQL_ALLOW_EMPTY_PASSWORD=true" -d -p 3306:3306 mysql

```

#### 2\. Setup test data

```bash
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
( 'jack', 'bauer');

```

#### 3\. Actual Example and Explanation Now

Open two different terminals, I'll call them **T1** and **T2** and start typing in the order specified by the comments:

```bash
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

Notice that T2 did not block, even though we're in a transaction. What does this mean? It means that the remainder of each transaction is made with an assumption about how the data was at the start of the transaction. If both threads start marching forward and want to update that data without optimistic locking, then one will be overwriting the other one:

```bash
#### T1 - DON'T ACTUALLY EXECUTE THIS
UPDATE mytable SET second_column = 'jackson' where prim_key = 1;

COMMIT;

#### T2 - DON'T ACTUALLY EXECUTE THIS
UPDATE mytable SET second_column = 'johnson' where prim_key = 1;

COMMIT;

```

Depending on the order of these two distinct transactions, one is going to be overwriting the other without knowing that the data had changed midway through--the second\_column could be either "jackson" or "johnson". There are some use cases where this isn't that big of a deal and many others where it is _definitely a big deal_, especially if the engineer writing the application doesn't understand that this is going to happen.

#### Optimistic Locking - A Practice, not a Database Feature

Optimistic Locking "fixes" this problem by observing some attribute about the data that it is changing, and if that value has changed the code will roll back the transaction. This can be made atomic in two ways: first, MySQL will hold open a lock on data that is being UPDATED (not selected, by default), and second, include the piece of data in the actual update as a WHERE condition, so that if the operation fails we can see the number of rows that were updated. If the number of rows that were updated is zero, then it's an optimistic locking exception and we should roll back:

```bash
#### T1 - Pay attention to the output
UPDATE mytable SET second_column = 'jackson' where prim_key = 1;

# optimistic locking check:
UPDATE mytable SET version = version + 1 WHERE prim_key = 1 AND version = 1;

COMMIT;

#### T2 - Watch the output!
UPDATE mytable SET second_column = 'johnson' where prim_key = 1;

# optimistic locking check:
UPDATE mytable SET version = version + 1 WHERE prim_key = 1 AND version = 1;

# ^ no rows affected! Roll back the transaction
ROLLBACK;

```

If you run each of them in the right order, you will see the UPDATE on the second terminal pause until the first terminal commits the transaction, which makes this operation concurrent safe and more performant than setting the transaction isolation level to SERIALIZABLE.
