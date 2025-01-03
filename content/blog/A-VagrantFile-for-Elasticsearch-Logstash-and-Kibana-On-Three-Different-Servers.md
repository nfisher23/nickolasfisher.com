---
title: "A VagrantFile for Elasticsearch, Logstash, and Kibana (On Three Different Servers)"
date: 2018-11-18T13:42:46
draft: false
tags: [distributed systems, vagrant, bash, the elastic stack, DevOps]
---

[Elasticsearch, Logstash, and Kibana](https://www.elastic.co/), commonly referred to as ELK or the Elastic Stack, is a set of tools that can, well do a lot of things. It is most famous for its logging and analytics capabilities.

In a nutshell:

1. Elasticsearch is a distributed NoSQL database with automatic indexing, and is designed primarily for &#34;scalability&#34;--in other words, redundancy via sharding and clustering across multiple servers, and a document-based philosophy (and, you know, search).
2. Kibana is a dashboard designed primarily to be a GUI on top of the Elasticsearch database, with cool features like visualization.
3. Logstash can send formatted logs to Elasticsearch and filter out logs that aren&#39;t relevant, typically by receiving them from Filebeats.

This is not an exhaustive list of all the things you can do with these tools, and this isn&#39;t even taking into account [beats](https://www.elastic.co/products/beats), but is usually where people start when they are introduced to the Elastic Stack.

So, now we want to play around with all of it, and we&#39;ve decided to use [Vagrant](https://www.vagrantup.com/) to provision some local virtual machines. While this is a good starting point/sandbox, keep in mind that there is no security with the following setup, and in any production environment not having security baked in would be a very bad thing to do.

First, we&#39;ll set up the VagrantFile. Navigate to the directory you want to set this up in and type:

```bash
$ vagrant init -m
```

Then set up a VagrantFile like:

```
Vagrant.configure(&#34;2&#34;) do |config|
  config.vm.box = &#34;ubuntu/bionic64&#34;

  config.vm.provider :virtualbox do |vb|
    vb.memory = 3072
    vb.cpus = 1
  end

  config.vm.define &#34;elasticsearch&#34; do |elasticsearch|
    elasticsearch.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.111&#34;
    elasticsearch.vm.provision :shell, path: &#34;elasticsearch-provision.sh&#34;
  end

  config.vm.define &#34;kibana&#34; do |kibana|
    kibana.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.112&#34;
    kibana.vm.provision :shell, path: &#34;kibana-provision.sh&#34;
  end

  config.vm.define &#34;logstash&#34; do |logstash|
    logstash.vm.network &#34;private_network&#34;, ip: &#34;192.168.56.113&#34;
    logstash.vm.provision :shell, path: &#34;logstash-provision.sh&#34;
  end
end
```

You&#39;ll need three shell scripts in the same directory called &#34;elasticsearch-provision.sh&#34;, &#34;kibana-provision.sh&#34;, and &#34;logstash-provision.sh&#34;.

Let&#39;s start with the Elasticsearch shell script. From [the official Elasticsearch install guide for version 6.4](https://www.elastic.co/guide/en/elasticsearch/reference/6.4/index.html):

&gt; Elasticsearch requires at least Java 8. Specifically as of this writing,
&gt; it is recommended that you use the Oracle JDK version 1.8.0\_131.

So we need to:

1. Install Java 8

2. Install Elasticsearch
3. Configure it to listen on a specified port on the server
4. Ensure the service is running, and runs on server boot up time

The steps can be expressed in a bash script like so (elasticsearch-provision.sh):

```bash
#!/bin/bash

# install java 8
apt install -y software-properties-common
apt-add-repository -y ppa:webupd8team/java
apt update
echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
apt install -y oracle-java8-installer

# install elasticsearch
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.4.2.deb
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.4.2.deb.sha512
shasum -a 512 -c elasticsearch-6.4.2.deb.sha512
sudo dpkg -i elasticsearch-6.4.2.deb

# configure elasticsearch to be available on port 9200
sudo chmod 777 /etc/elasticsearch
sudo touch /etc/elasticsearch/elasticsearch.yml
sudo cat &lt;&lt; EOF &gt; /etc/elasticsearch/elasticsearch.yml
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 192.168.56.111
http.port: 9200-9300
EOF

echo &#34;restarting service...&#34;

service elasticsearch restart

# available on startup
update-rc.d elasticsearch defaults 95 10

```

If you run:

```bash
$ vagrant up elasticsearch

```

Then, after a few minutes of provisioning and letting the service get fully ramped up, you can

```
$ curl 192.168.56.111:9200

```

And you should see the Elasticsearch tagline response.

The setup for Kibana is a bit easier since we don&#39;t need to install Java (this is kibana-provision.sh):

```bash
#/bin/bash
wget https://artifacts.elastic.co/downloads/kibana/kibana-6.4.2-amd64.deb
shasum -a 512 kibana-6.4.2-amd64.deb
dpkg -i kibana-6.4.2-amd64.deb

# configure kibana to be available on port 5601 and connect to elasticsearch instance
chmod 777 /etc/kibana
touch /etc/kibana/kibana.yml
cat &lt;&lt; EOF &gt; /etc/kibana/kibana.yml
server.port: 5601
server.host: 192.168.56.112
elasticsearch.url: http://192.168.56.111:9200
EOF

service kibana restart

# available on startup
update-rc.d kibana defaults 95 10

```

Once this is up (run $ vagrant up kibana), you should be able to navigate to 192.168.56.112:5601 in your browser and see Kibana&#39;s dashboard come up.

Finally, here&#39;s the Logstash script (logstash-provision.sh):

```bash
#!/bin/bash

# install java 8
apt install -y software-properties-common
apt-add-repository -y ppa:webupd8team/java
apt update
echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
apt install -y oracle-java8-installer

# install logstash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
apt-get install apt-transport-https
echo &#34;deb https://artifacts.elastic.co/packages/6.x/apt stable main&#34; | sudo tee -a /etc/apt/sources.list.d/elastic-6.x.list
apt-get update &amp;&amp; apt-get install logstash

# configure logstash to be available on port 5044 and send to elasticsearch
sudo chmod 777 /etc/logstash
sudo touch /etc/logstash/conf.d/ex-pipeline.conf
sudo cat &lt;&lt; EOF &gt; /etc/logstash/conf.d/ex-pipeline.conf
input {
  beats {
    host =&gt; &#34;192.168.56.113&#34;
    port =&gt; &#34;5044&#34;
  }
}
output {
  elasticsearch {
    hosts =&gt; [ &#34;192.168.56.111:9200&#34; ]
  }
}
EOF

service logstash restart

```

You now have your playground, go conquer the world with it.
