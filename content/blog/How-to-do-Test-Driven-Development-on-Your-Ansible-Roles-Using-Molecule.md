---
title: "How to do Test Driven Development on Your Ansible Roles Using Molecule"
date: 2019-03-01T00:00:00
draft: false
---

You can see the sample code for this tutorial [on GitHub.](https://github.com/nfisher23/some-ansible-examples)

﻿ [Molecule](https://molecule.readthedocs.io/en/latest/) is primarily a way to manage the testing of infrastructure automation code. At its core, it wraps around various providers like Vagrant, Docker, or VMWare, and provides relatively simple integration with testing providers, notably [TestInfra](https://testinfra.readthedocs.io/en/latest/). Molecule is a great tool, but in my opinion there are not enough resources, by way of examples, to provide an adequate getting started guide. This post is meant to help fill that void.

You will need molecule, vagrant, VirtualBox, and Ansible installed on your machine to participate in the following exercise.

### Installing Java 11 Using Ansible

In a previous post, I showed a way to [install any version of Java using Ansible](https://nickolasfisher.com/blog/How-to-Provision-a-Server-with-Java-using-Ansible). However, I think the end result of that was not very modular. For example, I hardcoded several paths to directories, as well as output files that would be downloaded. For that simple example, it would probably be easy enough for me to refactor it and verify by hand, i.e. by ssh-ing into the VM and then running the appropriate commands. But that is not scalable. For code to properly evolve as requirements change and are refined, and for bugs to be fettered out successfully, automated tests reduce errors and improve time to delivery. So I went looking for a solution to automate the testing of ansible roles, and I stumbled upon Molecule.

First, navigate to the directory you want your Ansible role to reside, and initialize an Ansible role with a Molecule wrapper:

``` bash
$ molecule init role -d vagrant -r test-driven-development-with-molecule
```

As you can see, this example will use Vagrant as the provider. Molecule, as of this writing, defaults to Docker, which is a valid choice as well, however we&#39;ll focus on one thing at at time and work with a VM (even though it is slower) for now. The command above will simplify your life by providing boilerplate code that installs python on your target VM, which is required by Ansible. You _might_ have to modify the created VM in the platforms section of your **molecule/default/molecule.yml** instance like so:

``` yaml
platforms:
  - name: instance
    box: ubuntu/xenial64
    memory: 2048
    provider_raw_config_args:
    - &#34;customize [&#39;modifyvm&#39;, :id, &#39;--uartmode1&#39;, &#39;disconnected&#39;]&#34;

```

You will also want to update your **molecule/default/playbook.yml** to use **:**

``` yaml
become: yes

```

I want to [install the latest OpenJDK version 11 from the tarball](https://jdk.java.net/11/) on the official JDK release page. What does a finished install look like for me? Well, I can think of basically three things that constitute a valid Java install:

- Java is available on my PATH and $ java -version outputs a valid java runtime.
- Javac is available on the PATH and ﻿$ javac -version ﻿outputs a valid java compiler.
- JAVA\_HOME is set properly.

To stick with test driven development, I&#39;ll write a test for the java runtime using test infra first. Paste this code into your **molecule/default/tests/test\_default.py** file:

``` python
import os

import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ[&#39;MOLECULE_INVENTORY_FILE&#39;]).get_hosts(&#39;all&#39;)

