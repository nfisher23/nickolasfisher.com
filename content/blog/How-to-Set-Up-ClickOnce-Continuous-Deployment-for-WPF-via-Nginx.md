---
title: "How to Set Up ClickOnce Continuous Deployment for WPF via Nginx"
date: 2018-08-08T00:08:00
draft: false
tags: [c#, ngnix]
---

I&#39;ve been working on a small wpf project on GitHub that let&#39;s you [view SEC filings on your desktop](https://github.com/nfisher23/SEPubViewer) in an intuitive way. Since EDGAR kind of sucks for a casual user, this is much more appealing.

To deploy this solution, the most current technology is provided by Microsoft and called [ClickOnce](https://docs.microsoft.com/en-us/visualstudio/deployment/clickonce-security-and-deployment). If I&#39;m being frank, my experience with ClickOnce has left me pretty underwhelmed, mostly because to install something on a system without warning the user that their computer is about to be obliterated, a certificate needs to be obtained from a trusted CA. That would be fine, and in fact that&#39;s how SSL/TLS certificates work on the web, except that these certificates usually cost quite a bit of money for an individual developer, and from what I&#39;ve found there does not appear to be a [Let&#39;s Encrypt](https://letsencrypt.org/)-type solution which is, well, free. But you can still get ClickOnce working to publish an app, it just means your user is going to get a &#34;This is not a recognized publisher&#34; warning when you go ahead and give it to them. Not an ideal solution, but it does allow for faster continuous delivery of your WPF applications than creating a bunch of boilerplate code to check for updates via an API.

To successfully complete this tutorial, you will need [GitBash](https://gitforwindows.org/), your own VPS (I suggest [Digital Ocean](https://www.digitalocean.com/)), and a WPF application to deploy.

### Make a WPF app and Publish it

To get started, you must create a WPF application. You can use the one I&#39;m developing on GitHub if you like. Then go to the publish page by right-clicking on your csproj file, select `Properties`, then click on the `Publish` sidebar option. Here, click on `Publish Wizard...`.

First, it asks you where you want to publish the application. Select a local, **empty** directory, and for your Installation Folder URL, choose the base URL you&#39;re using to distribute the installation package. If you have a website, I suggest a subdomain like downloads.mydomain.com, which you&#39;ll have to configure the DNS settings for, obviously.

### Configure Nginx on Your Server

Now get on git bash and connect to your server via ssh (try [this DO article on ssh connection](https://www.digitalocean.com/community/tutorials/how-to-connect-to-your-droplet-with-ssh) if you&#39;re confused here). Once up there, install Nginx via `sudo apt-get install Nginx`. Now, choose a directory to place the files you&#39;re going to want Nginx to serve. I suggest something like /var/www/myapplicationfiles/. In your Nginx sites-enabled file, you can adjust the default server configuration ( `pico /etc/nginx/sites-enabled/default`) to look like this:

```
server {
        listen 80;
        listen[::]:80;

        server_name mysite.come www.mysite.com;

        location / {
                root /var/www/myapplicationfiles;
                index publish.htm;
        }
}
```

Finally, and this is the part that took me an embarrassingly long time to get exactly right, you have to configure the MIME type response to conform to how Windows wants you to conform to. To be specific, open up your /etc/nginx/mime.types file and add the following records:

```
application/x-ms-application    application;
application/x-ms-manifest       manifest;
application/octet-stream        deploy;
application/octet-stream        msu;
application/octet-stream        msp;
```

For more info, see [Server and Client Config Issues](https://docs.microsoft.com/en-us/visualstudio/deployment/server-and-client-configuration-issues-in-clickonce-deployments).

### Copy Your Publish WPF Directory To Your Server

Finally, we&#39;re ready to push this bad boy up. Exit out of your ssh session, navigate to the folder where you published your WPF application, and (if you&#39;re inside the folder), type `scp -r * root@yourdomain:/var/www/myapplicationfiles/`. Hit enter, and you should be good to go. If you head to yourdomain.com/, it will serve up your install page (which looks pretty weak at the start). If you install the program, every time you run it thereafter it will check the domain you publish to for updates. If the version number is greater than the version number on file, it will prompt the user and automatically update. No admin privileges required.

To get rid of the annoying &#34;this isn&#39;t a trusted app&#34; box, like I said, you&#39;ll have to pay for a not-so-cheap certificate from a CA, and renew that certificate every year or so. That barrier to entry is going to inhibit the growth of WPF applications on Windows Desktops, which is a shame, because WPF is actually pretty neat technology.

Also, don&#39;t use git to push the files up via a repo and a post-receive file. For some reason (probably due to an interpreted change in the .manifest file from what I can tell), this causes problems. And it will make you a sad debugging panda.
