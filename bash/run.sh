#!/bin/bash

# Copy the PY scripts from the local ./src folder into the Master. (recursive for all files in the directory)
scp -r -i $pem_file ./src ubuntu@$master_dns:~/
ssh master

# Setup master-worker configuration
/usr/local/spark/sbin/start-all.sh

# Regenerate environment variables and run Spark script
rm logfile.log
source /usr/local/spark/conf/spark-env.sh
source ~/.profile
master_priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
spark-submit \
	--packages com.amazonaws:aws-java-sdk:1.7.4,org.apache.hadoop:hadoop-aws:2.7.7 \
	--conf spark.executor.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--conf spark.driver.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--master local ./src/chess-etl.py

