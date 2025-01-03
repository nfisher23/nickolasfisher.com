---
title: "A Fast SCSS Learning Feedback Loop With Harp and BrowserSync"
date: 2019-05-18T17:12:55
draft: false
---

If, like me, your development career has been firmly on servers, wiring and protecting data across multiple machine and focusing on architecture, the shift to building websites that &#34;look right&#34; can sometimes be a tough transition. Like all things engineering, ensuring that you have a short feedback loop, where you can interact with the tool that you&#39;re using in a very hands on way, will be your fastest and surest way to mastery.

There are two very different parts to any web application: the style of the page and the business logic of the page. Both of these parts will more or less need to know about the _structure_ of the page \[though limiting that from a CSS perspective is quite important as well\], but the style and the business logic can exist in harmony and separate out their concerns. Coming from the back end, business logic is no problem--unit test, code, unit test, code, refactor, more unit tests and code. Structure isn&#39;t even a problem, because HTML is very simple. When we start throwing in CSS is where traditional system level developers get thrown out of their comfort zone.

In learning [SCSS](https://sass-lang.com/documentation/syntax), which is a great tool to prevent duplication in plain-text CSS files, I found a simple sandbox setup that will help any developer get up and running as quickly as possible, using [harp](http://harpjs.com/) and [browsersync](https://www.browsersync.io/).

### The Environment

First, ensure that you have harp and browser sync installed globally:

```bash
$ npm install -g browser-sync
$ npm install -g harp
```

Note that, depending on how you installed npm, you might have to prepend either or both of the above commands with **sudo**.

Then, set up a simple project directory like so:

```
index.html
run.sh
css/
-- _variables.scss
-- main.scss

```

To start with, you can set up your **index.html** file to look like:

```html
&lt;html&gt;
    &lt;head&gt;
        &lt;link href=&#34;css/main.css&#34; type=&#34;text/css&#34; rel=&#34;stylesheet&#34;&gt;
    &lt;/head&gt;
    &lt;body&gt;
       &lt;p&gt; Some stuff &lt;/p&gt;
       &lt;p&gt;Some other stuff&lt;/p&gt;
       &lt;p&gt;Some other stuff&lt;/p&gt;
    &lt;/body&gt;
&lt;/html&gt;

```

Your **\_variables.scss** file can look like:

```css
$something: red;
```

Your **main.scss** file could look like:

```css
@import &#34;variables&#34;;

body {
    font: 12px Helvetica, Arial, sans-serif;
    color: $something;
}

```

Finally, your **run.sh** file could look like:

```bash
#!/bin/bash
harp server &amp;
browser-sync start --proxy &#39;localhost:9000&#39; --files &#39;**, *.html, *.scss&#39;
```

If you&#39;re on a \*nix operating system, be sure to set the permissions to run this file:

```bash
$ sudo chmod 755 ./run.sh
```

You should then be able to run:

```bash
$ ./run.sh
[Browsersync] Proxying: http://localhost:9000
[Browsersync] Access URLs:
 -------------------------------------
       Local: http://localhost:3000
    External: http://192.168.0.20:3000
 -------------------------------------
          UI: http://localhost:3001
 UI External: http://localhost:3001
 -------------------------------------
[Browsersync] Watching files...
------------
Harp v0.30.0 – Chloi Inc. 2012–2015
Your server is listening at http://localhost:9000/
Press Ctl&#43;C to stop the server

```

By opening up [http://localhost:3000,](http://localhost:3000,) any changes you make to your source files will be automatically reloaded in your browser window, enabling you to immediately see the style changes.

Go forth and conquer.
