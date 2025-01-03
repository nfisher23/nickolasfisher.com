---
title: "How To Create a Kubernetes Cluster on Digital Ocean using Terraform"
date: 2020-05-17T21:58:17
draft: false
tags: [DevOps, digital ocean, terraform, kubernetes]
---

The source code for this post can be found [on Github](https://github.com/nfisher23/digitalocean-terraform-examples/tree/master/kubernetes).

Kubernetes has democratized the cloud more than any piece of software before or since. What used to be proprietary APIs by AWS, Azure, or GCP for things like auto scaling groups, load balancers, or virtual machines is now abstracted away behind never ending yaml configuration. Combine this wonderful abstraction with the pricing model of [Digital Ocean](https://www.digitalocean.com/) and you've got all the makings of a developer party.

To spin up a simple digital ocean kubernetes cluster to play around with, I decided to use terraform:

```yaml
provider "digitalocean" {
  // token automatically picked up using env variables
}

variable "region" {
  # `doctl kubernetes options regions` for full list
  default = "sfo3"
}

data "digitalocean_kubernetes_versions" "do_k8s_versions" {}

output "k8s-versions" {
  value = data.digitalocean_kubernetes_versions.do_k8s_versions.latest_version
}

resource "digitalocean_kubernetes_cluster" "hellok8s" {
  name    = "hellok8s"
  region  = var.region
  # Or grab the latest version slug from `doctl kubernetes options versions`
  version = data.digitalocean_kubernetes_versions.do_k8s_versions.latest_version

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-2gb"
    node_count = 1
  }
}

```

You'll need to set an environment variable for terraform to pick up the credentials necessary to actually run this \[DIGITALOCEAN\_ACCESS\_TOKEN\]. Here, I'm using a [terraform data source](https://www.terraform.io/docs/providers/do/d/kubernetes_versions.html) to provide the version to use, since digital ocean changes the versions that they are supporting on a regular basis. This kubernetes cluster will not be dynamically spinning up and down DO infrastructure, instead it will have a single worker node. I also have elected to use the third San Fransisco data center. If you want to find out what data centers can support this, you can run:

```
$ doctl kubernetes options regions
```

If you navigate to the directory where the above file (I called it **kubs.tf**) is located, run:

```
$ terraform apply
```

And wait about five minutes, it will finally come up. If you go and [configure doctl, the command line client for digital ocean](https://github.com/digitalocean/doctl), then you should be able to see your cluster with:

```
$ doctl kubernetes cluster list
ID                                      Name        Region    Version        Auto Upgrade    Status     Node Pools
02522c88-9c46-4a4e-9776-a7e1e229b13a    hellok8s    sfo3      1.17.5-do.0    false           running    worker-pool

```

You can save the context for the [kubectl cli utility](https://kubernetes.io/docs/tasks/tools/install-kubectl/) with:

```
$ doctl kubernetes cluster kubeconfig save hellok8s

```

Then you should be able to start running kubernetes commands:

```
$ kubectl get deployments -A
NAMESPACE     NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   cilium-operator        1/1     1            1           18m
kube-system   coredns                2/2     2            2           18m
kube-system   kubelet-rubber-stamp   1/1     1            1           18m
```

And you're good to go.
