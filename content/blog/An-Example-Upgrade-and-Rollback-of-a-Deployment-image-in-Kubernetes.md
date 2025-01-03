---
title: "An Example Upgrade and Rollback of a Deployment image in Kubernetes"
date: 2020-06-20T22:47:02
draft: false
tags: [java, spring, DevOps, kubernetes, kind]
---

In this article, I'm going to show you how to bootstrap a local kubernetes cluster with a custom image, debug it, deploy a new image, then rollback to the old image.

If you don't have a good way to get a local kubernetes cluster, you should check out: [how to setup and use kind locally](https://nickolasfisher.com/blog/How-to-Setup-and-Use-Kubernetes-in-Docker-kind). Big fan.

## Create Cluster, Make Base Resources

Start by creating a local kubernetes cluster using [kind](https://kind.sigs.k8s.io/):

```
kind create cluster
```

This will automatically configure your **kubectl** cli to communicate to your local cluster (called "kind" by default).

I have created [a sample repository in Docker Hub](https://hub.docker.com/repository/docker/nfisher23/simplesb) with a few different versions that we'll use for this demo. Specifically, there are two versions (both tags):

- **v2**: has just an **/actuator/health** endpoint
- **v3**: added a GET **/hello** endpoint

Once we have our cluster, we can first create a namespace with this yaml:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nick-sample-sb

```

You can apply this with:

```bash
kubectl apply -f namespace.yaml

```

We can then add a deployment, which will live in that created namespace, and will start with version 2:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nick-sample-sb
  namespace: nick-sample-sb
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nick-sample-sb
  template:
    metadata:
      labels:
        app: nick-sample-sb
    spec:
      containers:
        - name: nick-sample-sb
          image: nfisher23/simplesb:v2
          imagePullPolicy: Always
          ports:
            - containerPort: 8080

```

Pretty much the same command to get this up there:

```bash
kubectl apply -f deployment.yaml

```

Finally, we'll expose a way for other pods in the cluster to communicate with the pods managed by the deployment (actually, the deployment manages ReplicaSets, which in turn ensure we have enough pods) with one more yaml for cluster ip:

```yaml
apiVersion: v1
kind: Service
metadata:
  namespace: nick-sample-sb
  name: nick-sample-sb-clusterip
  labels:
    app: nick-sample-sb
spec:
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    app: nick-sample-sb

```

And apply that change:

```bash
kubectl apply -f service.yaml

```

Note that, while I have shown these examples as being in three different yaml files, they could technically all be in one. It's usually easier to keep them more isolated, but if you're just proving things out/sandboxing, you can do so by separating them with **--**.

## Debugging

Okay, we have our namespace:

```bash
$ kubectl get namespaces | grep nick-sample-sb
nick-sample-sb       Active   29m

```

We also have a deployment with two pods, hopefully ready by now:

```bash
$ kubectl get deployment --namespace nick-sample-sb nick-sample-sb
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
nick-sample-sb   2/2     2            2           30m

```

We can see some more details about those pods specifically with something like:

```bash
$ kubectl get pods --namespace nick-sample-sb -o wide
NAME                              READY   STATUS    RESTARTS   AGE   IP           NODE           NOMINATED NODE   READINESS GATES
nick-sample-sb-7f65cbf9fc-bc4pw   1/1     Running   0          16m   10.244.1.5   kind-worker
nick-sample-sb-7f65cbf9fc-kd95d   1/1     Running   0          17m   10.244.1.5   kind-worker

```

Because CoreDNS is included with this version of kubernetes and it is a cluster aware DNS service, our cluster ip will automatically allow us to communicate via a DNS entry **nick-sample-sb-clusterip** if we are in the same namespace. Let's prove that--we can exec onto one of the pods and send a curl to the health endpoint:

```bash
$ POD=$(kubectl get pods -n nick-sample-sb | grep nick-sample | awk '{print $1}' | head -1)
$ kubectl exec --namespace nick-sample-sb $POD -- curl nick-sample-sb-clusterip/actuator/health
{"status":"UP","components":{"diskSpace":{"status":"UP","details":{"total":117610516480,"free":57556758528,"threshold":10485760}},"ping":{"status":"UP"}}}

```

We can also notice that our **/hello** endpoint is not available:

```bash
$ kubectl exec --namespace nick-sample-sb $POD -- curl nick-sample-sb-clusterip/hello
{"timestamp":"2020-06-27T23:38:46.663+0000","status":404,"error":"Not Found","message":"No message available","path":"/hello"}

```

Now, we are ready to ship our code, version 3--we can do so from the cli with:

```bash
$ kubectl set image -n nick-sample-sb deployments/nick-sample-sb nick-sample-sb=nfisher23/simplesb:v3 --record
deployment.apps/nick-sample-sb image updated

```

This command will update to the latest version and after all the pods come up, we can see that our **/hello** endpoint exists:

```bash
$ POD=$(kubectl get pods -n nick-sample-sb | grep nick-sample | awk '{print $1}' | head -1)
$ kubectl exec --namespace nick-sample-sb $POD -- curl nick-sample-sb-clusterip/hello
hello

```

I hope this provided you with enough information to get you started bridging the gap between applications and infra when it comes to kubernetes.
