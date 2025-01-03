---
title: "How to Create a Digital Ocean Droplet using Terraform"
date: 2020-05-17T18:26:02
draft: false
tags: [bash, DevOps, digital ocean, terraform]
---

The source code for this post can be found [on Github](https://github.com/nfisher23/digitalocean-terraform-examples).

Terraform lets you define your infrastructure, e.g. a virtual machine, in code. Used properly, this saves you a lot of time, makes infra easier to manage, and will generally limit your ability to do something dumb, like delete or modify something your infrastructure is dependent on.

The official [digital ocean terraform provider](https://www.terraform.io/docs/providers/do/index.html) makes this pretty straightforward. In this article, we will:

1. Get the prerequisites for using the DO terraform provider out of the way
2. Add your ssh key to your digital ocean account using terraform

3. Create a droplet
4. Provision nginx on that droplet

## Getting it Done

To begin with, you will need a digital ocean api key. You can get one by going to the digital ocean control panel, clicking "API" under "Account" in the lower left hand corner, then "Generate New Token." I would recommend you use a sophisticated secrets management tool like [Encryptr](https://spideroak.com/encryptr/) to keep the api token safe, since you're only going to get to see the token immediately after you create it.

Once you have the key, you need to set an environment variable in your shell like so:

```
export DIGITALOCEAN_ACCESS_TOKEN=<your-token-here>
```

If you've already set up your digital ocean cli before then you could try [a yaml bash tool called yq](https://mikefarah.gitbook.io/yq/) to set it for you:

```
export DIGITALOCEAN_ACCESS_TOKEN=$(cat ~/.config/doctl/config.yaml |  yq r - access-token)
```

### Reuse Existing SSH Key

If you already have a ssh key that you uploaded to digital ocean in some other way, you can import it as terraform data, so that your terraform configuration can look like this (in this case, I'm using an old thinkpad retrofitted with linux, so I have an ssh key I've named "thinkpad"):

```hcl
provider "digitalocean" {
  // token automatically picked up using env variable DIGITALOCEAN_ACCESS_TOKEN
}

variable "region" {
  default = "sfo2"
}

data digitalocean_ssh_key "my_ssh_key" {
  name = "thinkpad"
}

resource "digitalocean_droplet" "atest" {
  image      = "ubuntu-18-04-x64"
  name       = "test"
  region     = var.region
  size       = "s-1vcpu-2gb"
  ssh_keys   = [data.digitalocean_ssh_key.my_ssh_key.id]
  monitoring = true
  private_networking = true
}

output "droplet_ip_address" {
  value = digitalocean_droplet.atest.ipv4_address
}

```

## Create SSH Key

If you want to upload your ssh key to digital ocean in this terraform configuration as well, then you can set this up as:

```yaml
provider "digitalocean" {
  // token automatically picked up using env variable DIGITALOCEAN_ACCESS_TOKEN
}

variable "region" {
  default = "sfo2"
}

resource "digitalocean_ssh_key" "my_ssh_key" {
  name = "new_ssh_key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "digitalocean_droplet" "atest" {
  image      = "ubuntu-18-04-x64"
  name       = "test"
  region     = var.region
  size       = "s-1vcpu-2gb"
  ssh_keys   = [digitalocean_ssh_key.my_ssh_key.id]
  monitoring = true
  private_networking = true
}

output "droplet_ip_address" {
  value = digitalocean_droplet.atest.ipv4_address
}

```

With your chosen terraform configuration in place, navigate to the directory where this is set up and run:

```
$ terraform init
$ terraform apply

```

Then type "yes" on prompt, and you should see two resources being created.

### Installing Nginx

Once it is up and running, you should be able to install nginx on this server with the following set of commands:

```
$ export IP_ADDR=$(terraform output droplet_ip_address)
$ ssh root@$IP_ADDR "sudo apt-get update &amp;&amp; sudo apt-get install -y nginx"

```

To view the IP address in your shell:

```
$ echo $IP_ADDR

```

You should now be able to navigate on your browser to that IP address and see the canned nginx homepage.
