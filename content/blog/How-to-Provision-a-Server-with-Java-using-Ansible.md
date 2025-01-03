---
title: "How to Provision a Server with Java using Ansible"
date: 2018-11-18T17:15:01
draft: false
tags: [java, ansible, DevOps]
---

In my post about [how to provision any version of Java using a bash script](https://nickolasfisher.com/blog/How-to-Provision-a-Linux-Server-With-Any-Version-of-Java-via-a-Bash-Script), we saw that:

```bash
#!/bin/bash

# Get tarball for JDK 10.0.1
wget https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz

# make java 10 directory
mkdir -p /usr/lib/java10

# unpack tarball
tar -C /usr/lib/java10/ -xvzf ./openjdk-10.0.1_linux-x64_bin.tar.gz

# update alternatives
update-alternatives --install /usr/bin/java java /usr/lib/java10/jdk-10.0.1/bin/java 20000
update-alternatives --install /usr/bin/javac javac /usr/lib/java10/jdk-10.0.1/bin/javac 20000

# verify with a version check
java -version
```

Will get you openJDK version 10.0.1 from the tarball in the link.

While that script works, it&#39;s generally a better idea to make this more maintainable. For example, if we re-run this bash script on a server that is already provisioned, it will run all of these steps again. In this case, nothing bad will actually happen, but it can lead to some sticky debug sessions when we start to move to more complicated provisioning steps.

We&#39;ll convert this bash script to an [ansible](https://www.ansible.com/) playbook. To test this, we&#39;ll set up a VagrantFile like so:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;ubuntu/bionic64&#34;
  config.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.115&#34;

  config.vm.provider :virtualbox do |vb|
    vb.memory = 1024
    vb.cpus = 1
  end

  config.vm.provision &#34;ansible&#34; do |ansible|
    ansible.playbook = &#34;provision.yml&#34;
  end
end
```

We&#39;ll need an ansible playbook in the same directory called &#34;provision.yml&#34;. We are using Ubuntu 18 (bionic64), which does not come with python 2 installed. Since ansible defaults to python 2, one way to deal with that problem is to install it prior to running the playbook. We can&#39;t gather facts before installing it, because gathering facts requires, you guessed it, python 2:

```yaml
---
- hosts: all
  become: yes
  gather_facts: no
  pre_tasks:
    - name: &#39;install python2 on ubuntu 18&#39;
      raw: test -e /usr/bin/python || (apt-get -y update &amp;&amp; apt-get install -y python-minimal)

  tasks:
    - name: Gather facts
      setup:

```

This bash command checks if we have python first, and only updates and gets python-minimal if it&#39;s not already there. The empty **setup:** command runs the gathering of facts and we can proceed like we never had to do this weird pre-provisioning step in the first place.

We can convert these two steps to:

```bash
# Get tarball for JDK 10.0.1
wget https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz

# make java 10 directory
mkdir -p /usr/lib/java10
```

To:

```yaml
    - name: Get Java tarball
      get_url:
        url: https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz
        dest: /etc/open-jdk10.tar.gz

    - name: make java 10 directory
      file:
        path: /usr/lib/java10
        state: directory

```

Which uses ansible&#39;s get\_url module to download the tarball and move it to the /etc/open-jdk10.tar.gz location, only downloading it if we haven&#39;t already done so. We then create the directory we eventually want to put java10 into

We can then convert:

```bash
# unpack tarball
tar -C /usr/lib/java10/ -xvzf ./openjdk-10.0.1_linux-x64_bin.tar.gz
```

Into:

```yaml
    - name: unpack tarball
      unarchive:
        dest: /usr/lib/java10
        src: /etc/open-jdk10.tar.gz
        remote_src: yes
```

This unpacks the tarball and places it into the directory previously created.

Finally, we will update alternatives (and, as a bonus, we&#39;ll set the JAVA\_HOME environment variable):

```yaml
    - name: update alternatives for java
      alternatives:
        name: java
        path: /usr/lib/java10/jdk-10.0.1/bin/java
        link: /usr/bin/java
        priority: 20000

    - name: set java home as environment variable
      blockinfile:
        insertafter: EOF
        path: /etc/environment
        block: export JAVA_HOME=/usr/lib/java10/jdk-10.0.1

```

The final ansible playbook looks like:

```yaml
---
- hosts: all
  become: yes
  gather_facts: no
  pre_tasks:
    - name: &#39;install python2 on ubuntu 18&#39;
      raw: test -e /usr/bin/python || (apt-get -y update &amp;&amp; apt-get install -y python-minimal)

  tasks:
    - name: Gather facts
      setup:

    - name: Get Java tarball
      get_url:
        url: https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz
        dest: /etc/open-jdk10.tar.gz

    - name: make java 10 directory
      file:
        path: /usr/lib/java10
        state: directory

    - name: unpack tarball
      unarchive:
        dest: /usr/lib/java10
        src: /etc/open-jdk10.tar.gz
        remote_src: yes

    - name: update alternatives for java
      alternatives:
        name: java
        path: /usr/lib/java10/jdk-10.0.1/bin/java
        link: /usr/bin/java
        priority: 20000

    - name: set java home as environment variable
      blockinfile:
        insertafter: EOF
        path: /etc/environment
        block: export JAVA_HOME=/usr/lib/java10/jdk-10.0.1

```

Happy provisioning!
