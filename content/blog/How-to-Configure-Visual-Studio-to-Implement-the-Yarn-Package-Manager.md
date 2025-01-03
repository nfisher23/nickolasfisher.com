---
title: "How to Configure Visual Studio to Implement the Yarn Package Manager"
date: 2018-08-08T00:00:00
draft: false
tags: [c#]
---

The old recommended way of getting packages like bootstrap and jquery easily into
a project was to use bower. That was convenient to add packages for projects where you were planning on providing
mostly server-side functionality, and could use bootstrap to handle page styling, for example.

Now, [the official bower page for microsoft](https://docs.microsoft.com/en-us/aspnet/core/client-side/bower)
recommends that you use [Yarn](https://yarnpkg.com/en/). Yarn is good, but you do have to fiddle with it a bit
to get automatic installation of the packages into your real project.

### Getting Yarn Installed

First, if you don&#39;t have Node.js, [install Node.js here](https://nodejs.org/en/).
Then, head over to the [Yarn download page](https://yarnpkg.com/en/docs/install) and get Yarn installed on your box.

### Use a Convienent Add On

I use a good visual studio extension by Mads Kristensen to get VS to use package.json in the same way that bower.json works, which is located [here](https://marketplace.visualstudio.com/items?itemName=MadsKristensen.YarnInstaller). Per the instructions on that page, after you install it, for Visual Studio 2017 you have to make sure you set the Yarn Installer &#34;Install on save&#34; and disable the npm restore options.

### Add and manipulate the .yarnrc file

Finally, what we (I, I&#39;m guessing you do too) really would like is to have packages installed in the _wwwroot/lib_ folder on saving the _package.json_ file. As it currently stands, if you add bootstrap in your package.json file like so:

```
{
  &#34;version&#34;: &#34;1.0.0&#34;,
  &#34;name&#34;: &#34;asp.net&#34;,
  &#34;private&#34;: true,
  &#34;devDependencies&#34;: {
    &#34;bootstrap&#34;: &#34;4.0.0&#34;
  }
}
```

Yarn will install the package in a node\_modules folder, which is inside the project folder but not, by default, visible to Visual Studio. To change this, we need to add a _[.yarnrc](https://yarnpkg.com/en/docs/yarnrc)_ file. The _.yarnrc_ file will let us configure additional features when the yarn command is run in the background by VS. In my case, I want new packages to be downloaded and saved to the wwwroot/lib folder, so I will add this line to my _.yarnrc_ file:

```
--install.modules-folder &#34;./wwwroot/lib&#34;

```

And presto! Now, if you add bootstrap, as before, it will save the distribution files to the _wwwroot/lib_ folder.

I hope you enjoyed this post. Please contact me if you would like further clarification or if you think I have made an error.
