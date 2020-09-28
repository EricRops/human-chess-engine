#!/bin/bash

# Video from Bastian on setting up VPC and security groups
# https://www.youtube.com/watch?v=3taULsvuZUM&feature=youtu.be

# Plus Tony Kwan (real hero) EC2-Spark setup doc!
# https://docs.google.com/document/d/1imilIqNRS58O8QdrlztZ69UGGvCXzXD4qggffSKXACs/edit#

# Setup permissions for AWS CLI Systems Manager (ssm) commands
# Needs AmazonSSM, DecodeAuthorizationMessage, and PassRole permission policies attached to IAM user group.
# https://docs.aws.amazon.com/systems-manager/latest/userguide/walkthrough-cli.html

ec2_ids=`aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' \
--filters Name=instance-state-name,Values=running \
--output text`

command="touch ~/hello.txt"
aws ssm send-command --instance-ids $ec2_ids --document-name "AWS-RunShellScript" --parameters "commands=$command" --output text

###### ABOVE SECTION DOESN'T WORK :( ############################

# Install Java and Scala (ALL INSTANCES)
sudo apt update
sudo apt install openjdk-8-jre-headless
# java -version
sudo apt install scala
# scala -version

# Install Spark (MASTER ONLY!!!!)
wget http://mirrors.ibiblio.org/apache/spark/spark-2.4.7/spark-2.4.7-bin-hadoop2.7.tgz
# Copy the install files to all the workers 
scp spark-2.4.7-bin-hadoop2.7.tgz worker1:~/
scp spark-2.4.7-bin-hadoop2.7.tgz worker2:~/

# DO THIS SECTION FOR ALL INSTANCES
# Extract the Spark tgz files and move them to /usr/local/spark
tar xvf spark-2.4.7-bin-hadoop2.7.tgz
sudo mv spark-2.4.7-bin-hadoop2.7/ /usr/local/spark

# Add spark/bin to the PATH environment variable
echo 'export PATH=/usr/local/spark/bin:$PATH' >> ~/.profile
source ~/.profile

# python3 --version (should have 3.6.9 with this Ubuntu image)



########### FINAL SETUP SECTION FOR MASTER ONLY ###############
# Configure Spark to keep track of its workers
# contents of /usr/local/spark/conf/spark-env.sh
rm /usr/local/spark/conf/spark-env.sh
sudo cp /usr/local/spark/conf/spark-env.sh.template /usr/local/spark/conf/spark-env.sh
master_priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
echo 'export SPARK_MASTER_HOST=$master_priv_ip' >> /usr/local/spark/conf/spark-env.sh.temmplate
echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> /usr/local/spark/conf/spark-env.sh.template
# For PySpark use
echo 'export PYSPARK_PYTHON=python3' >> /usr/local/spark/conf/spark-env.sh.template
sudo cp /usr/local/spark/conf/spark-env.sh.template /usr/local/spark/conf/spark-env.sh
source /usr/local/spark/conf/spark-env.sh

# Put the private IPs of the workers in the file /usr/local/spark/conf/slaves
rm /usr/local/spark/conf/slaves
workers_priv_ip=$(grep --only-matching --perl-regex "(?<=HostName\ ).*" ~/.ssh/config)
workers_ip_str=($workers_priv_ip)
echo -en '\n' >> /usr/local/spark/conf/slaves.template 
echo "${workers_ip_str[0]}" >> /usr/local/spark/conf/slaves.template 
echo "${workers_ip_str[1]}" >> /usr/local/spark/conf/slaves.template
sudo cp /usr/local/spark/conf/slaves.template /usr/local/spark/conf/slaves

# Install AWS CLI on Master





