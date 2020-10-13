#!/bin/bash
# Awesome article on Cassandra and performance
# https://www.scnsoft.com/blog/cassandra-performance

# Set profile to Insight credentials
export AWS_PROFILE=insight
pem_file="~/.ssh/eric-rops-IAM-keypair.pem"
num_nodes=3
type="m5.2xlarge"

# Get master DNS string
master_dns=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[?AmiLaunchIndex==`0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

# Cleanup backup data from Cassandra (all nodes)
ssh worker1
sudo du -h --max-depth=1
# ./apache-cassandra-3.11.8/bin/nodetool clearsnapshot

# Copy the PY scripts from local into the Master. (recursive for all files in the directory)
scp -r -i $pem_file ./database-scripts ubuntu@$master_dns:~/
ssh cassandra

# Start up cluster (all nodes, starting with the seeds)
cassandra
./apache-cassandra-3.11.8/bin/nodetool status

# Create Cassandra tables - BE VERY CAREFUL AS THIS DELETES THEM FIRST 
# python3 ./database-scripts/create-tables.py

# Monitor the nodes during writing
watch -n 1 nodetool tpstats

# Run Cassandra queries
board_state="rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq"
python3 ./database-scripts/queries.py "$board_state"

# Access the DB through CQLSH
master_priv_ip=$(ip addr show ens5 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
./apache-cassandra-3.11.8/bin/cqlsh $master_priv_ip 9042 --cqlversion="3.4.4"

# Alias: alias cql='./apache-cassandra-3.11.8/bin/cqlsh "PRIV_IP_ADDR" 9042 --cqlversion="3.4.4"'

# Keyspace stats
./apache-cassandra-3.11.8/bin/nodetool tablestats chessdb.games
./apache-cassandra-3.11.8/bin/nodetool tablestats chessdb.moves
./dsbulk-1.7.0/bin/dsbulk count -h $master_priv_ip -k chessdb -t games
./dsbulk-1.7.0/bin/dsbulk count -h $master_priv_ip -k chessdb -t moves


# Stop the Cassandra service
pkill -f CassandraDaemon

