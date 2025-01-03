---
title: "How to do Test Driven Development on Your Ansible Roles Using Molecule"
date: 2019-03-03T20:18:22
draft: false
tags: [vagrant, ansible, DevOps, molecule]
---

You can see the sample code for this tutorial [on GitHub.](https://github.com/nfisher23/some-ansible-examples)

﻿ [Molecule](https://molecule.readthedocs.io/en/latest/) is primarily a way to manage the testing of infrastructure automation code. At its core, it wraps around various providers like Vagrant, Docker, or VMWare, and provides relatively simple integration with testing providers, notably [TestInfra](https://testinfra.readthedocs.io/en/latest/). Molecule is a great tool, but in my opinion there are not enough resources, by way of examples, to provide an adequate getting started guide. This post is meant to help fill that void.

You will need molecule, vagrant, VirtualBox, and Ansible installed on your machine to participate in the following exercise.

### Installing Java 11 Using Ansible

In a previous post, I showed a way to [install any version of Java using Ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Server-with-Java-using-Ansible). However, I think the end result of that was not very modular. For example, I hardcoded several paths to directories, as well as output files that would be downloaded. For that simple example, it would probably be easy enough for me to refactor it and verify by hand, i.e. by ssh-ing into the VM and then running the appropriate commands. But that is not scalable. For code to properly evolve as requirements change and are refined, and for bugs to be fettered out successfully, automated tests reduce errors and improve time to delivery. So I went looking for a solution to automate the testing of ansible roles, and I stumbled upon Molecule.

First, navigate to the directory you want your Ansible role to reside, and initialize an Ansible role with a Molecule wrapper:

```bash
$ molecule init role -d vagrant -r test-driven-development-with-molecule
```

As you can see, this example will use Vagrant as the provider. Molecule, as of this writing, defaults to Docker, which is a valid choice as well, however we&#39;ll focus on one thing at at time and work with a VM (even though it is slower) for now. The command above will simplify your life by providing boilerplate code that installs python on your target VM, which is required by Ansible. You _might_ have to modify the created VM in the platforms section of your **molecule/default/molecule.yml** instance like so:

```yaml
platforms:
  - name: instance
    box: ubuntu/xenial64
    memory: 2048
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;

```

You will also want to update your **molecule/default/playbook.yml** to use **:**

```yaml
become: yes

```

I want to [install the latest OpenJDK version 11 from the tarball](https://jdk.java.net/11/) on the official JDK release page. What does a finished install look like for me? Well, I can think of basically three things that constitute a valid Java install:

- Java is available on my PATH and $ java -version outputs a valid java runtime.
- Javac is available on the PATH and ﻿$ javac -version ﻿outputs a valid java compiler.
- JAVA\_HOME is set properly.

To stick with test driven development, I&#39;ll write a test for the java runtime using test infra first. Paste this code into your **molecule/default/tests/test\_default.py** file:

```python
import os

import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ[&#39;MOLECULE_INVENTORY_FILE&#39;]).get_hosts(&#39;all&#39;)

# validate java runtime
def test_java_runtime(host):
    cmd = host.run(&#34;java -version&#34;)
    assert cmd.rc == 0
    assert cmd.stderr.find(&#34;11.0&#34;)
```

You can run:

```bash
$ molecule create
```

To create the local Vagrant VM you&#39;re going to test with, and you can run:

```bash
$ molecule converge
```

To run the Ansible playbook (which right now is empty) against your target machine. After running those two commands you can successfully run your test, created above, with:

```bash
$ molecule verify

```

You should see the test fail, which is a good thing--that means you have a test that _means_ something.

We can now insert some valid code to just barely pass the above test. Go to your **tasks/main.yml** file and add the following four tasks:

```yaml
- name: Get Java tarball
  get_url:
    url: https://download.java.net/java/GA/jdk11/9/GPL/openjdk-11.0.2_linux-x64_bin.tar.gz
    dest: /etc/open-jdk11.tar.gz

- name: make java 11 directory
  file:
    path: /usr/lib/java11
    state: directory

- name: unpack tarball
  unarchive:
    dest: /usr/lib/java11
    src: /etc/open-jdk11.tar.gz
    remote_src: yes

- name: update alternatives for java
  alternatives:
    name: java
    path: /usr/lib/java11/jdk-11.0.2/bin/java
    link: /usr/bin/java
    priority: 20000

```

The above tasks:

1. Downloads the OpenJDK 11.0.2 version tarball for Linux, and places the downloaded tar.gz. file under /etc/
2. Creates a directory to store the extracted java11 version
3. Unarchives (decompresses and unpacks) the tar.gz file into a directory
4. Uses the alternatives system to add java to a place that is already on our path, in this case /usr/bin

You should be able to run:

```bash
$ molecule converge &amp;&amp; molecule verify
```

And see our one test pass.

We can take a shortcut and create two tests for the next two requirements that successfully install Java on our target machine:

```python
def test_java_compiler(host):
    cmd = host.run(&#34;javac -version&#34;)
    assert cmd.rc == 0
    assert cmd.stderr.find(&#34;11.0&#34;)

def test_java_home_configured(host):
    f = host.file(&#34;/etc/environment&#34;)
    assert f.contains(&#34;JAVA_HOME=/usr/lib/&#34;)

```

Here, I want to validate that the java compiler is on our PATH and that its version contains 11.0. I could have been more specific here, but I want the tests to be flexible enough to allow for changes and this was the compromise that I struck. In the second test, it&#39;s my goal to ensure that the **/etc/environment** file, which sets environment variables for every user on our system, has the JAVA\_HOME variable defined--again, it&#39;s a tradeoff between being so specific that its not flexible to change and so vague that it&#39;s meaningless, so I stuck with saying that JAVA\_HOME should start with /usr/lib.

We could also write a test that runs an ﻿$ echo $JAVA\_HOME command and interprets the response, which is probably more robust in the long run.

You should then be able to run:

```bash
$ molecule converge &amp;&amp; molecule verify
```

And see both tests failing. We can append the following two tasks to our **tasks/main.yml** file to make the tests pass:

```yaml
- name: update alternatives for javac
  alternatives:
    name: javac
    path: /usr/lib/java11/jdk-11.0.2/bin/javac
    link: /usr/bin/javac
    priority: 20000

- name: set java home as environment variable
  blockinfile:
    insertafter: EOF
    path: /etc/environment
    block: export JAVA_HOME=/usr/lib/java11/jdk-11.0.2

```

Now, running:

```bash
$ molecule converge &amp;&amp; molecule verify
```

Should have both tests pass.

Probably the most difficult part going forward will be understanding how to leverage test infra to write the appropriate tests. The best resource I&#39;ve found is simply the listing of modules at [https://testinfra.readthedocs.io/en/latest/modules.html](https://testinfra.readthedocs.io/en/latest/modules.html,)--from there I have just been tinkering with it to get used to how it all works.

A big reason that we write these tests is so that we can refactor our work. I would encourage you to take the code above and modularize it--e.g. change the download url, use a register to get the tar.gz location, and reuse anything that looks duplicated. Because this is focused on introducing molecule, I&#39;ll leave you here.
