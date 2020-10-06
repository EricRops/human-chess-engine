#!/bin/bash
# For reference, command to remove bottom line of file: sed -i '$ d' foo.txt

# Video from Bastian on setting up VPC and security groups
# https://www.youtube.com/watch?v=3taULsvuZUM&feature=youtu.be

# Plus Tony Kwan (real hero) EC2-Spark setup doc!
# https://docs.google.com/document/d/1imilIqNRS58O8QdrlztZ69UGGvCXzXD4qggffSKXACs/edit#

# Setup permissions for AWS CLI Systems Manager (ssm) commands
# Needs AmazonSSM, DecodeAuthorizationMessage, and PassRole permission policies attached to IAM user group.
# TRIED THIS THE FIRST TIME to send commands to multiple EC2 machines at once, did not work :(. Much sadness.
# https://docs.aws.amazon.com/systems-manager/latest/userguide/walkthrough-cli.html

# Set profile to Insight credentials
export AWS_PROFILE=insight
pem_file="~/.ssh/eric-rops-IAM-keypair.pem"
worker_num_nodes=4
master_num_nodes=1
master_type="m5a.large"
worker_type="c5.2xlarge"

aws ec2 run-instances \
	--image-id ami-07a29e5e945228fa1 \
	--count $master_num_nodes \
	--instance-type $master_type \
	--region us-west-2 \
	--placement AvailabilityZone=us-west-2a \
	--associate-public-ip-address \
	--subnet-id subnet-0ae35fa0d9ebe1010 \
	--key-name eric-rops-IAM-keypair \
	--security-group-ids sg-04bf65989d4033a0b sg-0bd1097bda280de96 sg-0d774a6a1bfebe338 \
	--ebs-optimized \
	--block-device-mapping "[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 5000 } } ]"
	
master_dns=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[*].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$master_type \
--output text)

master_priv_ip=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[*].[PrivateIpAddress]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$master_type \
--output text)

workers_dns=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[*].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$worker_type \
--output text)

workers_priv_ip=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[*].[PrivateIpAddress]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$worker_type \
--output text)

# Convert strings to arrays to access individual IPs
workers_dns_str=($workers_dns)
workers_ip_str=($workers_priv_ip) 


# Setup passwordless SSH (required for Spark clusters)
# SSH into master node
ssh -i $pem_file ubuntu@$master_dns

# Generate authorization key (within the master node)
ssh-keygen -t rsa -P ""

# Append this key to the authorized_keys file
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# Can now access the master node using `ssh localhost`

# back to local laptop
exit

# Append the same id_rsa.pub credentials from the master instance to all the workers
# The pipe "|" operator. It takes the output from the left side, and inserts it as input into the right side
ssh -i $pem_file ubuntu@$master_dns 'cat ~/.ssh/id_rsa.pub' | ssh -i $pem_file ubuntu@${workers_dns_str[0]} 'cat >> ~/.ssh/authorized_keys'
ssh -i $pem_file ubuntu@$master_dns 'cat ~/.ssh/id_rsa.pub' | ssh -i $pem_file ubuntu@${workers_dns_str[1]} 'cat >> ~/.ssh/authorized_keys'
ssh -i $pem_file ubuntu@$master_dns 'cat ~/.ssh/id_rsa.pub' | ssh -i $pem_file ubuntu@${workers_dns_str[2]} 'cat >> ~/.ssh/authorized_keys'
ssh -i $pem_file ubuntu@$master_dns 'cat ~/.ssh/id_rsa.pub' | ssh -i $pem_file ubuntu@${workers_dns_str[3]} 'cat >> ~/.ssh/authorized_keys'

# Set local machine and master config files for easy SSH access between nodes

# Create config file on local machine (once), and made it readable and writable by the user ONLY
rm ~/.ssh/config
touch ~/.ssh/config
chmod 600 ~/.ssh/config
echo "Host master" >> ~/.ssh/config
echo "    HostName $master_dns" >> ~/.ssh/config
echo "    IdentityFile $pem_file" >> ~/.ssh/config
echo "    User ubuntu" >> ~/.ssh/config
echo "    Port 22" >> ~/.ssh/config

# Create config file for master (for easy access to workers. ex: ssh worker1)
rm ~/.ssh/config_master
touch ~/.ssh/config_master
chmod 600 ~/.ssh/config_master
echo "Host worker1" >> ~/.ssh/config_master
echo "    HostName ${workers_ip_str[0]}" >> ~/.ssh/config_master
echo "    User ubuntu" >> ~/.ssh/config_master
echo "    Port 22" >> ~/.ssh/config_master
echo "Host worker2" >> ~/.ssh/config_master
echo "    HostName ${workers_ip_str[1]}" >> ~/.ssh/config_master
echo "    User ubuntu" >> ~/.ssh/config_master
echo "    Port 22" >> ~/.ssh/config_master
echo "Host worker3" >> ~/.ssh/config_master
echo "    HostName ${workers_ip_str[2]}" >> ~/.ssh/config_master
echo "    User ubuntu" >> ~/.ssh/config_master
echo "    Port 22" >> ~/.ssh/config_master
echo "Host worker4" >> ~/.ssh/config_master
echo "    HostName ${workers_ip_str[3]}" >> ~/.ssh/config_master
echo "    User ubuntu" >> ~/.ssh/config_master
echo "    Port 22" >> ~/.ssh/config_master

# Copy config_master into the master node, and rename to config  
scp -i $pem_file ~/.ssh/config_master ubuntu@$master_dns:~/.ssh/config

# SSH into master node again, and make sure you have easy access into the workers from the master
ssh master
ssh worker1

# Install Java and Scala and PIP (ALL INSTANCES)
sudo apt update
sudo apt install openjdk-8-jre-headless
# java -version
sudo apt install scala
# scala -version
# Install PIP and python-chess library on all nodes
curl -O https://bootstrap.pypa.io/get-pip.py
sudo apt-get install python3-distutils
python3 get-pip.py --user
echo -en '\n' >> ~/.profile
echo 'export PATH=~/.local/bin:$PATH' >> ~/.profile
source ~/.profile
pip -V
pip install python-chess

# Install AWS CLI on MASTER
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

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
# python3 -V (should have 3.6.9 with this Ubuntu image)


########### FINAL SETUP SECTION FOR MASTER ONLY ###############
# Configure Spark to keep track of its workers
rm /usr/local/spark/conf/spark-env.sh
master_priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
echo "export SPARK_MASTER_HOST=${master_priv_ip}" >> /usr/local/spark/conf/spark-env.sh.template
echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> /usr/local/spark/conf/spark-env.sh.template
echo 'export PYSPARK_PYTHON=python3' >> /usr/local/spark/conf/spark-env.sh.template

# Additional Spark Tuning

sudo cp /usr/local/spark/conf/spark-env.sh.template /usr/local/spark/conf/spark-env.sh
source /usr/local/spark/conf/spark-env.sh

# Put the private IPs of the workers in the file /usr/local/spark/conf/slaves
rm /usr/local/spark/conf/slaves
workers_priv_ip=$(grep --only-matching --perl-regex "(?<=HostName\ ).*" ~/.ssh/config)
workers_ip_str=($workers_priv_ip)
echo -en '\n' >> /usr/local/spark/conf/slaves.template 
echo "${workers_ip_str[0]}" >> /usr/local/spark/conf/slaves.template 
echo "${workers_ip_str[1]}" >> /usr/local/spark/conf/slaves.template
echo "${workers_ip_str[2]}" >> /usr/local/spark/conf/slaves.template
echo "${workers_ip_str[3]}" >> /usr/local/spark/conf/slaves.template
# Comment out the local host machine (doesn't seem right to be there)
sed -i -e '19s/^/# /' /usr/local/spark/conf/slaves.template
sudo cp /usr/local/spark/conf/slaves.template /usr/local/spark/conf/slaves

exit
# Make sure that the AWS credentials are stored as user environment variables in the ~/.profile file. 
# It seems that we only need to do this on master.
scp -i $pem_file ~/.aws/credentials ubuntu@$master_dns:~/
ssh master
# Copy the two lines containing the appropriate credentials (with "export" at the beginning of both lines)
sed -n '6,7p' credentials >> ~/.profile
# cat -n ~/.profile |||||| to see which lines to insert "export" at the beginning of 
sed -i -e '31,32s/^/export /' ~/.profile
source ~/.profile
rm credentials

