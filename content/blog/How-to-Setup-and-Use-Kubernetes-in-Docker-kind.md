---
title: "How to Setup and Use Kubernetes in Docker [kind]"
date: 2020-06-01T00:00:00
draft: false
---

[kind](https://kind.sigs.k8s.io/) is a tool that spins up a kubernetes cluster of arbitrary size on your local machine. It is, in my experience, more lightweight than minikube, and also allows for a multi node setup.

## Install

To install kind, I would recommend using [homebrew](https://brew.sh/) if you&#39;re on \*nix:

```
$ brew install kind

```

and [chocolatey](https://chocolatey.org/) if you&#39;re on windows:

```
choco install kind
```

You will want to already have [docker installed](https://docs.docker.com/get-docker/) as well as [kubectl installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

## Basic Usage

If you just type

```
$ kind create cluster

```

It will:

- Create a single node kubernetes cluster called &#34;kind&#34; using docker on your local machine

- Automatically configure your **kubectl** cli tool to point at this cluster

We can see that with a couple of commands:

```
$ docker container ls -a
CONTAINER ID        IMAGE                  COMMAND                  CREATED             STATUS              PORTS                       NAMES
78e981f32e68        kindest/node:v1.18.2   &#34;/usr/local/bin/entr…&#34;   4 minutes ago       Up 4 minutes        127.0.0.1:39743-&gt;6443/tcp   kind-control-plane

$ kubectl get nodes -A
NAME                 STATUS   ROLES    AGE    VERSION
kind-control-plane   Ready    master   4m7s   v1.18.2

$ kubectl get deployments -n kube-system
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
coredns   2/2     2            2           4m35s

```

## Multi Node Cluster Configuration

We can control the type of cluster that gets created with a [custom kind config file](https://kind.sigs.k8s.io/docs/user/configuration/) \[let&#39;s call this one **my-kind-config.yaml**\]:

```
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
