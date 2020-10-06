#!/bin/bash
# For reference, command to remove bottom line of file: sed -i '$ d' foo.txt

# Video from Bastian on setting up VPC and security groups
# https://www.youtube.com/watch?v=3taULsvuZUM&feature=youtu.be

# Plus Tony Kwan (real hero) EC2-Spark setup doc!
# https://docs.google.com/document/d/1imilIqNRS58O8QdrlztZ69UGGvCXzXD4qggffSKXACs/edit#

# Set profile to Insight credentials
export AWS_PROFILE=insight
pem_file="~/.ssh/eric-rops-IAM-keypair.pem"
num_nodes=3
type="m5.large"

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
	--block-device-mapping "[ { \"DeviceName\": \"/dev/xvda\", \"Ebs\": { \"VolumeSize\": 200 } } ]"
	
# 	--iam-instance-profile Name=SSMInstanceProfile
	
master_dns=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[?AmiLaunchIndex==`0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

master_priv_ip=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[?AmiLaunchIndex==`0`].[PrivateIpAddress]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

workers_dns=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[?AmiLaunchIndex > `0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

workers_priv_ip=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[?AmiLaunchIndex > `0`].[PrivateIpAddress]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
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

# Copy config_master into the master node, and rename to config  
scp -i $pem_file ~/.ssh/config_master ubuntu@$master_dns:~/.ssh/config

# SSH into master node again, and make sure you have easy access into the workers from the master
ssh master
ssh worker1

# Now move onto spark_setup.sh


# Terminate the instances
ec2_ids=`aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' \
--filters Name=instance-state-name,Values=running \
--output text`

aws ec2 terminate-instances --instance-ids $ec2_ids