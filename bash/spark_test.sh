#!/bin/bash

####### ALL TESTS DONE THROUGH THE MASTER INSTANCE ###############
# Test if Spark is working (initiate all the instances and setup the master-worker 
# configuration. This starts it as a background process so you can exit the terminal).
/usr/local/spark/sbin/start-all.sh

# Test that Spark is installed correctly
/usr/local/spark/bin/run-example SparkPi 10

# Next, test that PySpark is working properly
spark-submit /usr/local/spark/examples/src/main/python/pi.py 10

# Finally, test that Spark can run on the cluster. You should be able to see workers’ private IPs among the output
spark-submit --master spark://$master_priv_ip:7077 /usr/local/spark/examples/src/main/python/pi.py 10

# Once you want to stop you can run:
/usr/local/spark/sbin/stop-all.sh


####### TEST S3 File Access ###########
# Make sure that the AWS credentials are stored as user environment variables in the ~/.profile file. 
# It seems that we only need to do this on master.
scp -i $pem_file ~/.aws/credentials ubuntu@$master_dns:~/
ssh master
# Copy the two lines containing the appropriate credentials (with "export" at the beginning of both lines)
sed -n '6,7p' credentials >> ~/.profile
# cat -n ~/.profile |||||| to see which lines to insert "export" at the beginning of 
sed -i -e '29,30s/^/export /' ~/.profile
source ~/.profile
rm credentials

# Copy the PY scripts from the ./src folder into the Master. (recursive for all files in the directory)
scp -r -i $pem_file ./src ubuntu@$master_dns:~/
ssh master

# Run script!
source /usr/local/spark/conf/spark-env.sh
# source ~/.profile
spark-submit \
	--packages com.amazonaws:aws-java-sdk:1.7.4,org.apache.hadoop:hadoop-aws:2.7.7 \
	--conf spark.executor.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--conf spark.driver.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--master local ./src/test_spark_s3.py

# Same test but with the cluster
master_priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
/usr/local/spark/sbin/start-all.sh
spark-submit \
	--packages com.amazonaws:aws-java-sdk:1.7.4,org.apache.hadoop:hadoop-aws:2.7.7 \
	--conf spark.executor.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--conf spark.driver.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--master spark://$master_priv_ip:7077 ./src/test_spark_s3.py
	
/usr/local/spark/sbin/stop-all.sh

# Manbir's command
spark-submit --packages com.amazonaws:aws-java-sdk:1.7.4,org.apache.hadoop:hadoop-aws:2.7.7  \
	--conf spark.executor.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--conf spark.driver.extraJavaOptions=-Dcom.amazonaws.services.s3.enableV4=true \
	--master spark:// yourmasterDNShere:7077 etl_json2parquet_v1.py


