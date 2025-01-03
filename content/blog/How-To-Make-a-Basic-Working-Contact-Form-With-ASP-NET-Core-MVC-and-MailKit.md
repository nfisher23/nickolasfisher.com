---
title: "How To Make a Basic Working Contact Form With ASP .NET Core MVC and MailKit"
date: 2018-08-04T00:00:00
draft: false
tags: [c#, .NET Core MVC]
---

Modern day website owners prefer not to leave their email address open and exploitable on the internet.
Enter the Contact page, which will usually have some basic fields for the visitor of the site to fill out like
Name, Email Address, Phone, and Message to send to someone who can help them out.

Enough talk. Let's code up a working contact form with ASP .NET Core MVC!

Let's start with the front-end. Open up Visual Studio, and create a new ASP .Net Core Web Application project. I'm calling mine BasicContactForm.
When prompted, choose the **Empty** project template. Then ensure your startup class looks like this:

```
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;

namespace BasicContactForm
{
    public class Startup
    {
        public void ConfigureServices(IServiceCollection services)
        {
            services.AddMvc();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            app.UseMvcWithDefaultRoute();
        }
    }
}
```

We'll first need a model for the contact form to bind to, so add a **Models Folder** and add a class called **ContactFormModel**.
It's a real simple container class like so:

```
namespace BasicContactForm.Models
{
    public class ContactFormModel
    {
        public string Name { get; set; }
        public string Email { get; set; }
        public string Message { get; set; }
    }
}
```

The default route we configured in `Startup` is Home/Index, so to work with that we have to create a **Controllers Folder** and
place a class called **HomeController** inside it like so (we'll add the post method in a minute for the form):

```
using Microsoft.AspNetCore.Mvc;

namespace BasicContactForm.Controllers
{
    public class HomeController : Controller
    {
        [HttpGet]
        public ViewResult Index()
        {
            return View();
        }
    }
}
```

Now we need a **Views Folder** with a **Home Folder** inside the Views Folder. Then add a Razor page (cshtml) titled Index.cshtml, inside the Home Folder, like so:

```
@addTagHelper *, Microsoft.AspNetCore.Mvc.TagHelpers
@model BasicContactForm.Models.ContactFormModel

<h3>Basic Contact Form</h3>
<form asp-action="Index" asp-controller="Home" method="post">
    <div>
        <label asp-for="Name">Please enter your name:</label>
        <input type="text" asp-for="Name" />
    </div>
    <div>
        <label asp-for="Email">Please enter your email:</label>
        <input type="text" asp-for="Email" />
    </div>
    <div>
        <label asp-for="Message">Please enter your message:</label>
        <textarea asp-for="Message"></textarea>
    </div>
    <input type="submit" value="Send Message!" />
</form>
```

At this point you should be able to run the code and get a basic contact form. Try to submit the form and it will fail, though, because we don't have a method that consumes post requests. In a real project we'd obviously want to style the page, and we would also want to add the tag helpers for the whole project by using a `_ViewImports.cshtml`, but we'll stay focused on getting it functional for this example.

We will use [MailKit](https://github.com/jstedfast/MailKit) to send an email from and to an address of our choosing on the backend. So add MailKit via Nuget. Then create
some container classes to hold Email related information like so (add them in the `Models` folder):

For the basic address information:

```
namespace BasicContactForm.Models
{
    public class EmailAddress
    {
        public string Name { get; set; }
        public string Address { get; set; }
    }
}
```

For the message:

```
using System.Collections.Generic;

namespace BasicContactForm.Models
{
    public class EmailMessage
    {
        public List<EmailAddress> ToAddresses { get; set; } = new List<EmailAddress>();
        public List<EmailAddress> FromAddresses { get; set; } = new List<EmailAddress>();
        public string Subject { get; set; }
        public string Content { get; set; }
    }
}
```

Finally, we need some information about the configuration of the SmtpServer. The conventional port is 587, so I've included an optional constructor argument to change that:

```
namespace BasicContactForm.Models
{
    public class EmailServerConfiguration
    {
        public EmailServerConfiguration(int _smtpPort = 587)
        {
            SmtpPort = _smtpPort;
        }

        public string SmtpServer { get; set; }
        public int SmtpPort { get; }
        public string SmtpUsername { get; set; }
        public string SmtpPassword { get; set; }
    }
}
```

MailKit is a dependency. It appears to be a very functional dependency, but since it is "out of our hands," it would be wise to set up our code to not rely on its functionality going forward.
Interfaces to the rescue. We'll create an interface and take advantage of the auto-magical dependency injection feature that asp provides (later):

```
namespace BasicContactForm.Models
{
    public interface IEmailService
    {
        void Send(EmailMessage message);
    }
}
```

The MailKit implementation will take information about the server in the constructor, and we'll use the same auto-magic DI feature in a bit:

```
using System.Linq;
using MimeKit;

namespace BasicContactForm.Models
{
    public class MailKitEmailService : IEmailService
    {
        private readonly EmailServerConfiguration _eConfig;

        public MailKitEmailService(EmailServerConfiguration config)
        {
            _eConfig = config;
        }

        public void Send(EmailMessage msg)
        {
            var message = new MimeMessage();
            message.To.AddRange(msg.ToAddresses.Select(x => new MailboxAddress(x.Name, x.Address)));
            message.From.AddRange(msg.FromAddresses.Select(x => new MailboxAddress(x.Name, x.Address)));

            message.Subject = msg.Subject;

            message.Body = new TextPart("plain")
            {
                Text = msg.Content
            };

            using (var client = new MailKit.Net.Smtp.SmtpClient())
            {
                client.Connect(_eConfig.SmtpServer, _eConfig.SmtpPort);

                client.AuthenticationMechanisms.Remove("XOAUTH2");

                client.Authenticate(_eConfig.SmtpUsername, _eConfig.SmtpPassword);

                client.Send(message);
                client.Disconnect(true);
            }
        }
    }
}
```

To reduce a burden on future potential changes, as well as to improve testing capabilities, we'll apply the dependency injection in the startup class. It could now look like this:

```
using BasicContactForm.Models;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;

namespace BasicContactForm
{
    public class Startup
    {
        public void ConfigureServices(IServiceCollection services)
        {
            EmailServerConfiguration config = new EmailServerConfiguration
            {
                SmtpPassword = "Password",
                SmtpServer = "smtp.someserver.com",
                SmtpUsername = "awesomeemail@nickolasfisher.com"
            };

            EmailAddress FromEmailAddress = new EmailAddress
            {
                Address = "myemailaddress@somesite.com",
                Name = "Nick Fisher"
            };

            services.AddSingleton<EmailServerConfiguration>(config);
            services.AddTransient<IEmailService, MailKitEmailService>();
            services.AddSingleton<EmailAddress>(FromEmailAddress);
            services.AddMvc();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            app.UseMvcWithDefaultRoute();
        }
    }
}
```

We will update our HomeController to consume the necessary arguments in the constructor and to send the email to wherever we want.
For this example, we'll send an email to ourselves.

```
using BasicContactForm.Models;
using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;

namespace BasicContactForm.Controllers
{
    public class HomeController : Controller
    {
        private EmailAddress FromAndToEmailAddress;
        private IEmailService EmailService;
        public HomeController(EmailAddress _fromAddress,
            IEmailService _emailService)
        {
            FromAndToEmailAddress = _fromAddress;
            EmailService = _emailService;
        }

        [HttpGet]
        public ViewResult Index()
        {
            return View();
        }

        [HttpPost]
        public IActionResult Index(ContactFormModel model)
        {
            if (ModelState.IsValid)
            {
                EmailMessage msgToSend = new EmailMessage
                {
                    FromAddresses = new List<EmailAddress> { FromAndToEmailAddress },
                    ToAddresses = new List<EmailAddress> { FromAndToEmailAddress },
                    Content = $"Here is your message: Name: {model.Name}, " +
                        $"Email: {model.Email}, Message: {model.Message}",
                    Subject = "Contact Form - BasicContactForm App"
                };

                EmailService.Send(msgToSend);
                return RedirectToAction("Index");
            }
            else
            {
                return Index();
            }
        }
    }
}
```

Enter valid server credentials in the startup class and we're good to go! A few notes:

1. If you're using gmail, you will have to [let less secure apps use your account](https://support.google.com/accounts/answer/6010255?hl=en).
    Alternatively, you can jump through some more hoops to make your app more secure. In production it's probably wise to choose the latter.

2. If you are testing locally, antivirus software can often intercept the initial secure handshake that MailKit tries to make. In my case, I disabled Avast while testing
    and the emails went through without a hitch.
3. Consider handing off to another thread to actually send the email as it can take some time depending on the environment/resources available.
4. In practice, you will want to redirect to a different page, usually a "thanks for contacting us" page, which will tell the user that their message was received.
5. I would recommend having an appsettings.Development.json file and an appsettings.Production.json file, each with emails you don't regularly use do regularly use, respectively.
    This will allow you to test locally, and when you publish to production it will load the new settings.

I hope you enjoyed this post. Please get ahold of me if you need clarification or if you think I've made an error.
