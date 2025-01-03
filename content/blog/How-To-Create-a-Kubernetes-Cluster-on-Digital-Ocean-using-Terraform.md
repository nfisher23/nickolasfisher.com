---
title: "How To Create a Kubernetes Cluster on Digital Ocean using Terraform"
date: 2020-05-01T00:00:00
draft: false
---

The source code for this post can be found [on Github](https://github.com/nfisher23/digitalocean-terraform-examples/tree/master/kubernetes).

Kubernetes has democratized the cloud more than any piece of software before or since. What used to be proprietary APIs by AWS, Azure, or GCP for things like auto scaling groups, load balancers, or virtual machines is now abstracted away behind never ending yaml configuration. Combine this wonderful abstraction with the pricing model of [Digital Ocean](https://www.digitalocean.com/) and you&#39;ve got all the makings of a developer party.

To spin up a simple digital ocean kubernetes cluster to play around with, I decided to use terraform:

``` yaml
provider &#34;digitalocean&#34; {
  // token automatically picked up using env variables
}

variable &#34;region&#34; {
  # `doctl kubernetes options regions` for full list
  default = &#34;sfo3&#34;
}

data &#34;digitalocean_kubernetes_versions&#34; &#34;do_k8s_versions&#34; {}

output &#34;k8s-versions&#34; {
  value = data.digitalocean_kubernetes_versions.do_k8s_versions.latest_version
}

resource &#34;digitalocean_kubernetes_cluster&#34; &#34;hellok8s&#34; {
  name    = &#34;hellok8s&#34;
  region  = var.region
  # Or grab the latest version slug from `doctl kubernetes options versions`
  version = data.digitalocean_kubernetes_versions.do_k8s_versions.latest_version

  node_pool {
    name       = &#34;worker-pool&#34;
    size       = &#34;s-2vcpu-2gb&#34;
    node_count = 1
  }
}
```

You&#39;ll need to set an environment variable for terraform to pick up the credentials necessary to actually run this \[DIGITALOCEAN\_ACCESS\_TOKEN\]. Here, I&#39;m using a [terraform data source](https://www.terraform.io/docs/providers/do/d/kubernetes_versions.html) to provide the version to use, since digital ocean changes the versions that they are supporting on a regular basis. This kubernetes cluster will not be dynamically spinning up and down DO infrastructure, instead it will have a single worker node. I also have elected to use the third San Fransisco data center. If you want to find out what data centers can support this, you can run:

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

And you&#39;re good to go.


