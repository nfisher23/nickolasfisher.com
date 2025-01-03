---
title: "Java Date and Time: Instant, LocalDate, and TemporalAdjuster"
date: 2018-12-01T12:56:02
draft: false
---

Improvements to the Java 8 [Date and Time API](https://docs.oracle.com/javase/tutorial/datetime/iso/index.html)--in particular Instant, LocalDate/LocalDateTime, and their absolute counterpart ZonedDateTime, provide a much more intuitive and friendly way to deal with time than previous versions of Java.

### Instant

Instants represent a snapshot of time and assumes that time is a straight line. This is in contrast to something like LocalDateTime, which takes into account daylight savings transformations and other fun adjustments like leap years.

We can take the Instant of any moment with Instant.now(), and we can get the difference between them with Duration. Start a simple JUnit test file and begin it like so:

```java
    private static Instant start1;
    private static Instant end1;

    private static Instant start2;
    private static Instant end2;

    @BeforeClass
    public static void instants_differencing() throws Exception {
        start1 = Instant.now();
        Thread.sleep(15);
        end1 = Instant.now();

        start2 = Instant.now();
        Thread.sleep(90);
        end2 = Instant.now();
    }
```

Then we can get the difference between any two of them, and validate expectations, like:

```java
    @Test
    public void differenceBetweenTwoInstants() throws Exception {
        Duration timeElapsed = Duration.between(start1, end1);
        long milliseconds = timeElapsed.toMillis();
        assertTrue(milliseconds &gt;= 14 &amp;&amp; milliseconds &lt;= 16);
    }
```

We can compare two Durations using an intuitive, fluent API. Here we validate that the difference between the second set of start and end instants (start2 and end2) is five times or more farther apart on the timeline than the difference between first set of instants (start1 and end1):

```java
    @Test
    public void atLeastFiveTimesFaster() throws Exception {
        Duration timeElapsed1 = Duration.between(start1, end1);
        Duration timeElapsed2 = Duration.between(start2, end2);

        boolean isOverFiveTimesFaster = timeElapsed1.multipliedBy(5).minus(timeElapsed2).isNegative();
        assertTrue(isOverFiveTimesFaster);
    }
```

### LocalDate And TemporalAdjusters

A LocalDate is a meant to represent something like a calendar day. We can get the current date with LocalDate.now():

```java
    @Test
    public void localDate_now() {
        LocalDate today = LocalDate.now();
        System.out.println(today.toString());
    }

```

We can also construct any LocalDate using LocalDate.of(..), shown below. There are two quirks I believe important to point out about LocalDate. The first is that it&#39;s aware of leap years:

```java
    @Test
    public void localDate_knowsLeapYears() {
        LocalDate localDateInLeapYear = LocalDate.of(2020,1,1);
        int daysToAdd = 90;
        LocalDate leapYearPlusDays = localDateInLeapYear.plusDays(daysToAdd);

        LocalDate localDateInNonLeapYear = LocalDate.of(2018, 1,1);
        LocalDate nonLeapYearPlusDays = localDateInNonLeapYear.plusDays(daysToAdd);

        assertNotEquals(leapYearPlusDays.getDayOfMonth(), nonLeapYearPlusDays.getDayOfMonth());
    }

```

The second is the behavior of plusMonths(..), which will effectively truncate the end of a month if they have a different number of days between them. If two months have a different number of days and you&#39;re near the end of the month, it will reduce the day of the month if necessary to ensure you&#39;re only moving forward one calendar month.

For example, January has 31 days and February has 28 days. If we use plusMonths(1) from January 31st, we will get (in a non Leap Year) February 28th. No exceptions are thrown:

```java
    @Test
    public void localDate_plusMonths_returnsLastValidDate() {
        LocalDate endOfJanuary = LocalDate.of(2018,1,31);
        LocalDate endOfFebruary = endOfJanuary.plusMonths(1);

        assertEquals(28, endOfFebruary.getDayOfMonth());
    }

```

The days of the week start at 1, which is a Monday in LocalDate-speak. That implies that the end of the week is considered Sunday and has a value of 7:

```java
    @Test
    public void localDate_dayOfWeek() {
        DayOfWeek monday = LocalDate.of(1900,1,1).getDayOfWeek();

        assertEquals(&#34;MONDAY&#34;, monday.toString());
        assertEquals(1, monday.getValue());
    }

```

Finally, you can adjust any LocalDate in ways beyond just adding and subtracting days using [TemporalAdjusters](https://docs.oracle.com/javase/8/docs/api/java/time/temporal/TemporalAdjusters.html). For example, we can get the first Tuesday after today like:

```java
    @Test
    public void temporalAdjusters_getFirstTuesday() {
        LocalDate firstTuesday = LocalDate.of(2018, 6,1)
            .with(TemporalAdjusters.nextOrSame(DayOfWeek.TUESDAY));

        assertEquals(&#34;TUESDAY&#34;, firstTuesday.getDayOfWeek().toString());
    }

```

And we can get the second Monday in the month like:

```java
    @Test
    public void temporalAdjusters_getNthWeekdayInMonth() {
        LocalDate secondMondayInJune = LocalDate.of(2018, 6, 1)
            .with(TemporalAdjusters.dayOfWeekInMonth(2, DayOfWeek.MONDAY));

        assertEquals(LocalDate.of(2018,6,11), secondMondayInJune);
    }

```
