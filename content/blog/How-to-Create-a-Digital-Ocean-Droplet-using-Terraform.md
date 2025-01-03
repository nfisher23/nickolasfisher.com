---
title: "How to Create a Digital Ocean Droplet using Terraform"
date: 2020-05-17T18:26:02
draft: false
---

The source code for this post can be found [on Github](https://github.com/nfisher23/digitalocean-terraform-examples).

Terraform lets you define your infrastructure, e.g. a virtual machine, in code. Used properly, this saves you a lot of time, makes infra easier to manage, and will generally limit your ability to do something dumb, like delete or modify something your infrastructure is dependent on.

The official [digital ocean terraform provider](https://www.terraform.io/docs/providers/do/index.html) makes this pretty straightforward. In this article, we will:

1. Get the prerequisites for using the DO terraform provider out of the way
2. Add your ssh key to your digital ocean account using terraform

3. Create a droplet
4. Provision nginx on that droplet

## Getting it Done

To begin with, you will need a digital ocean api key. You can get one by going to the digital ocean control panel, clicking &#34;API&#34; under &#34;Account&#34; in the lower left hand corner, then &#34;Generate New Token.&#34; I would recommend you use a sophisticated secrets management tool like [Encryptr](https://spideroak.com/encryptr/) to keep the api token safe, since you&#39;re only going to get to see the token immediately after you create it.

Once you have the key, you need to set an environment variable in your shell like so:

```
export DIGITALOCEAN_ACCESS_TOKEN=&lt;your-token-here&gt;
```

If you&#39;ve already set up your digital ocean cli before then you could try [a yaml bash tool called yq](https://mikefarah.gitbook.io/yq/) to set it for you:

```
export DIGITALOCEAN_ACCESS_TOKEN=$(cat ~/.config/doctl/config.yaml |  yq r - access-token)
```

### Reuse Existing SSH Key

If you already have a ssh key that you uploaded to digital ocean in some other way, you can import it as terraform data, so that your terraform configuration can look like this (in this case, I&#39;m using an old thinkpad retrofitted with linux, so I have an ssh key I&#39;ve named &#34;thinkpad&#34;):

```hcl
provider &#34;digitalocean&#34; {
  // token automatically picked up using env variable DIGITALOCEAN_ACCESS_TOKEN
}

variable &#34;region&#34; {
  default = &#34;sfo2&#34;
}

data digitalocean_ssh_key &#34;my_ssh_key&#34; {
  name = &#34;thinkpad&#34;
}

resource &#34;digitalocean_droplet&#34; &#34;atest&#34; {
  image      = &#34;ubuntu-18-04-x64&#34;
  name       = &#34;test&#34;
  region     = var.region
  size       = &#34;s-1vcpu-2gb&#34;
  ssh_keys   = [data.digitalocean_ssh_key.my_ssh_key.id]
  monitoring = true
  private_networking = true
}

output &#34;droplet_ip_address&#34; {
  value = digitalocean_droplet.atest.ipv4_address
}

```

## Create SSH Key

If you want to upload your ssh key to digital ocean in this terraform configuration as well, then you can set this up as:

```yaml
provider &#34;digitalocean&#34; {
  // token automatically picked up using env variable DIGITALOCEAN_ACCESS_TOKEN
}

variable &#34;region&#34; {
  default = &#34;sfo2&#34;
}

resource &#34;digitalocean_ssh_key&#34; &#34;my_ssh_key&#34; {
  name = &#34;new_ssh_key&#34;
  public_key = file(&#34;~/.ssh/id_rsa.pub&#34;)
}

resource &#34;digitalocean_droplet&#34; &#34;atest&#34; {
  image      = &#34;ubuntu-18-04-x64&#34;
  name       = &#34;test&#34;
  region     = var.region
  size       = &#34;s-1vcpu-2gb&#34;
  ssh_keys   = [digitalocean_ssh_key.my_ssh_key.id]
  monitoring = true
  private_networking = true
}

output &#34;droplet_ip_address&#34; {
  value = digitalocean_droplet.atest.ipv4_address
}

```

With your chosen terraform configuration in place, navigate to the directory where this is set up and run:

```
$ terraform init
$ terraform apply

```

Then type &#34;yes&#34; on prompt, and you should see two resources being created.

### Installing Nginx

Once it is up and running, you should be able to install nginx on this server with the following set of commands:

```
$ export IP_ADDR=$(terraform output droplet_ip_address)
$ ssh root@$IP_ADDR &#34;sudo apt-get update &amp;&amp; sudo apt-get install -y nginx&#34;

```

To view the IP address in your shell:

```
$ echo $IP_ADDR

```

You should now be able to navigate on your browser to that IP address and see the canned nginx homepage.
