#!/bin/bash

# Set profile to Insight credentials
export AWS_PROFILE=insight
pem_file="~/.ssh/eric-rops-IAM-keypair.pem"
worker_num_nodes=5
master_num_nodes=1
master_type="m5a.large"
worker_type="m5.2xlarge"

# Get master DNS string
master_dns=$(aws ec2 describe-instances \
--query 'Reservations[0].Instances[?AmiLaunchIndex==`0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$master_type \
--output text)

# Cleanup spark worker folders
ssh worker1
sudo du -h --max-depth=1 /usr/local/spark/work/
rm -r /usr/local/spark/work/app*

# Copy the PY scripts from local into the Master. (recursive for all files in the directory)
scp -r -i $pem_file ./data-processing ubuntu@$master_dns:~/
ssh master

# TMUX windows so EC2 can still run after closing your ssh connection
tmux new -s mywindow # Run script here, leave whenever
tmux a -t mywindow   # When you log back in, come here to see progress

# Setup master-worker configuration
/usr/local/spark/sbin/start-all.sh

# Regenerate environment variables and run Spark script
source /usr/local/spark/conf/spark-env.sh
rm logfile.log
master_priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
spark-submit \
	--packages com.amazonaws:aws-java-sdk:1.7.4,org.apache.hadoop:hadoop-aws:2.7.7,datastax:spark-cassandra-connector:2.4.0-s_2.11 \
	--conf spark.sql.extensions=com.datastax.spark.connector.CassandraSparkExtensions \
	--conf spark.executor.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--conf spark.driver.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--conf spark.worker.cleanup.enabled=true \
	--conf spark.worker.cleanup.interval=1800 \
	--conf spark.serializer=org.apache.spark.serializer.KryoSerializer \
	--conf spark.driver.memory=6g \
	--conf spark.executor.memory=13g \
	--conf spark.executor.cores=4 \
	--conf spark.executor.instances=10 \
	--conf spark.sql.shuffle.partitions=300 \
	--master spark://$master_priv_ip:7077 ./data-processing/chesscom-etl.py
	
# Copy logfile to local machine
exit
scp -i $pem_file ubuntu@$master_dns:~/logfile.log ./logs
timestamp=$(date "+%F-%T")
mv ./logs/logfile.log ./logs/log-$timestamp.log


/usr/local/spark/sbin/stop-all.sh


## Spark parameters that made the job run slower
#	--conf spark.default.parallelism=100 \


