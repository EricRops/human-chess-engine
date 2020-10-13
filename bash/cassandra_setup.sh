#!/bin/bash

# Cassandra Setup Info:
# https://cassandra.apache.org/doc/latest/getting_started/installing.html
# https://maelfabien.github.io/bigdata/EC2_Cassandra/#

#### Cassandra does not use a Master-Worker architecture. 
#### But we will use the same master/worker ssh convention for convenience 

#### Therefore, do a similar EC2 setup as we did for Spark
export AWS_PROFILE=insight
pem_file="~/.ssh/eric-rops-IAM-keypair.pem"
num_nodes=3
type="m5.2xlarge"

aws ec2 run-instances \
	--image-id ami-07a29e5e945228fa1 \
	--count $num_nodes \
	--instance-type $type \
	--region us-west-2 \
	--placement AvailabilityZone=us-west-2a \
	--associate-public-ip-address \
	--subnet-id subnet-0ae35fa0d9ebe1010 \
	--key-name eric-rops-IAM-keypair \
	--security-group-ids sg-04bf65989d4033a0b sg-0bd1097bda280de96 sg-0d774a6a1bfebe338 \
	--ebs-optimized \
	--block-device-mapping "[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 400 } } ]"


# Must have the Spark cluster started first in order for these filters to work
master_dns=$(aws ec2 describe-instances \
--query 'Reservations[1].Instances[?AmiLaunchIndex==`0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

master_priv_ip=$(aws ec2 describe-instances \
--query 'Reservations[1].Instances[?AmiLaunchIndex==`0`].[PrivateIpAddress]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

workers_dns=$(aws ec2 describe-instances \
--query 'Reservations[1].Instances[?AmiLaunchIndex > `0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

workers_priv_ip=$(aws ec2 describe-instances \
--query 'Reservations[1].Instances[?AmiLaunchIndex > `0`].[PrivateIpAddress]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

# Convert strings to arrays to access individual IPs
workers_dns_str=($workers_dns)
workers_ip_str=($workers_priv_ip) 


# Setup passwordless SSH (required for clusters)
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

# Set local machine and master config files for easy SSH access between nodes

# Create config file on local machine (once), and made it readable and writable by the user ONLY
# NOTE: append to the ~./ssh/config file AFTER setting the Spark master name 
# rm ~/.ssh/config
# touch ~/.ssh/config_cass
chmod 600 ~/.ssh/config
echo "Host cassandra" >> ~/.ssh/config
echo "    HostName $master_dns" >> ~/.ssh/config
echo "    IdentityFile $pem_file" >> ~/.ssh/config
echo "    User ubuntu" >> ~/.ssh/config
echo "    Port 22" >> ~/.ssh/config

# Create config file for master (for easy access to workers. ex: ssh worker1)
rm ~/.ssh/config_cass
touch ~/.ssh/config_cass
chmod 600 ~/.ssh/config_cass
echo "Host worker1" >> ~/.ssh/config_cass
echo "    HostName ${workers_ip_str[0]}" >> ~/.ssh/config_cass
echo "    User ubuntu" >> ~/.ssh/config_cass
echo "    Port 22" >> ~/.ssh/config_cass
echo "Host worker2" >> ~/.ssh/config_cass
echo "    HostName ${workers_ip_str[1]}" >> ~/.ssh/config_cass
echo "    User ubuntu" >> ~/.ssh/config_cass
echo "    Port 22" >> ~/.ssh/config_cass

# Copy config_master into the master node, and rename to config  
scp -i $pem_file ~/.ssh/config_cass ubuntu@$master_dns:~/.ssh/config

# SSH into master node again, and make sure you have easy access into the workers from the master
ssh cassandra
ssh worker1

# Verify that Java is installed (ALL NODES)
sudo apt update
sudo apt install openjdk-8-jre-headless
java -version

# Install Cassandra!
wget https://downloads.apache.org/cassandra/3.11.8/apache-cassandra-3.11.8-bin.tar.gz
# Copy install files to all other nodes
scp apache-cassandra-3.11.8-bin.tar.gz worker1:~/
scp apache-cassandra-3.11.8-bin.tar.gz worker2:~/

# Repeat these steps for all nodes:
tar -xvf apache-cassandra-3.11.8-bin.tar.gz
# Set the necessary Env Variables
echo -en '\n' >> ~/.profile
echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64' >> ~/.profile
echo 'export JRE_HOME=$JAVA_HOME/jre' >> ~/.profile
echo 'export PATH=$JAVA_HOME/bin:$JAVA_HOME/jre/bin:$PATH' >> ~/.profile
echo 'export PATH=/home/ubuntu/apache-cassandra-3.11.8/bin:$PATH' >> ~/.profile
source ~/.profile 
rm apache-cassandra-3.11.8-bin.tar.gz



# CONFIGURE THE CLUSTER! (start with the Spark master node)

############ Modify the conf/cassandra.yaml file: ###################
clust_name="chess-platform"
priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
endpoint_snitch="Ec2Snitch"
# Concurrent writes: 8 * number of cores on node
concurrent_writes=64 
sed -i "/^\([[:space:]]*cluster_name: \).*/s//\1${clust_name}/" ./apache-cassandra-3.11.8/conf/cassandra.yaml
sed -i "/^\([[:space:]]*listen_address: \).*/s//\1${priv_ip}/" ./apache-cassandra-3.11.8/conf/cassandra.yaml
sed -i "/^\([[:space:]]*rpc_address: \).*/s//\1${priv_ip}/" ./apache-cassandra-3.11.8/conf/cassandra.yaml
sed -i "/^\([[:space:]]*endpoint_snitch: \).*/s//\1${endpoint_snitch}/" ./apache-cassandra-3.11.8/conf/cassandra.yaml
sed -i "/^\([[:space:]]*concurrent_writes: \).*/s//\1${concurrent_writes}/" ./apache-cassandra-3.11.8/conf/cassandra.yaml
# Seed nodes - Fow now, set 2 seed nodes (the "master" and worker1)
# cassandra.yaml: seeds: "255.31.31.255,255.31.31.255,255.31.31.255" (string IP addresses separated by a comma)
# Great info on seed nodes: https://www.quora.com/What-is-a-seed-node-in-Apache-Cassandra
# Add the master private IP to "seeds:" (could NOT figure out how to automate this part, sadness)
vi ./apache-cassandra-3.11.8/conf/cassandra.yaml

# Copy the yaml file to all other nodes!
scp ./apache-cassandra-3.11.8/conf/cassandra.yaml worker1:apache-cassandra-3.11.8/conf/cassandra.yaml
scp ./apache-cassandra-3.11.8/conf/cassandra.yaml worker2:apache-cassandra-3.11.8/conf/cassandra.yaml

# Edit the YAML file listen_address and rpc_address with each nodes private IP address. DO NOT CHANGE THE seed nodes
ssh worker1
priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
sed -i "/^\([[:space:]]*listen_address: \).*/s//\1${priv_ip}/" ./apache-cassandra-3.11.8/conf/cassandra.yaml
sed -i "/^\([[:space:]]*rpc_address: \).*/s//\1${priv_ip}/" ./apache-cassandra-3.11.8/conf/cassandra.yaml


############ Modify the conf/cassandra-rackdc.properties file: ###################
# For now, comment out the data center and rack lines
vi ./apache-cassandra-3.11.8/conf/cassandra-rackdc.properties
scp ./apache-cassandra-3.11.8/conf/cassandra-rackdc.properties worker1:apache-cassandra-3.11.8/conf/cassandra-rackdc.properties
scp ./apache-cassandra-3.11.8/conf/cassandra-rackdc.properties worker2:apache-cassandra-3.11.8/conf/cassandra-rackdc.properties


########### Install Python 2.7 so we can use the Cassandra Shell tool (CQLSH) - MASTER ONLY to start
sudo apt update
sudo apt install python2.7 python-pip
python2 -V
# pip2 -V

# Install PIP and cassandra python wrapper (for Python 3, MASTER ONLY)
curl -O https://bootstrap.pypa.io/get-pip.py
sudo apt-get install python3-distutils
python3 get-pip.py --user
# make sure ~/.local/bin is stored as an Env Variable in ~/.profile
echo -en '\n' >> ~/.profile
echo 'export PATH=~/.local/bin:$PATH' >> ~/.profile
source ~/.profile
pip -V
pip install cassandra-driver

# Install DS Bulk Loader to view table stats
curl -OL https://downloads.datastax.com/dsbulk/dsbulk-1.7.0.tar.gz
tar -xzvf dsbulk-1.7.0.tar.gz
rm dsbulk-1.7.0.tar.gz


# Do these steps on each machine (starting with the seed) to test the connection between every Cassandra node
./apache-cassandra-3.11.8/bin/cassandra
./apache-cassandra-3.11.8/bin/nodetool status # or describecluster


############ Get CQLSH working on the seed node first
# pip2 install cqlsh # CAREFUL, the pip install cqlsh tool has some bugs. Use the /usr/local/bin/cqlsh instead
priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
./apache-cassandra-3.11.8/bin/cqlsh $priv_ip 9042 --cqlversion="3.4.4"
# test cqlsh is working 
describe keyspaces;
SELECT * FROM system.peers LIMIT 10;
CREATE KEYSPACE IF NOT EXISTS chessdb WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 2 };
use chessdb;
DROP KEYSPACE IF EXISTS chessdb


# Stop the Cassandra service
pkill -f CassandraDaemon






