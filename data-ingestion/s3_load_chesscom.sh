#!/bin/bash
# LOAD DATA FROM CHESS.COM API into S3 (using an AWS EC2 machine)
# Based on calling a Python script from the end

## CREATE EC2 INSTANCE WITH MORE STORAGE TO CAN HANDLE UPLOADING LARGER FILES 
export AWS_PROFILE=insight
pem_file="~/.ssh/eric-rops-IAM-keypair.pem"
num_nodes=1
type="r5a.large"

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
	--block-device-mapping "[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 200 } } ]"
	
master_dns=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[?AmiLaunchIndex==`0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

# COPY OVER THE PY FILES (must be one level ABOVE the chess project root directory)
# The -r means recursive (all files)
# scp -r -i $pem_file chess-platform ubuntu@$master_dns:~/

# Make sure that the AWS credentials are stored as user environment variables in the ~/.profile file. 
scp -i $pem_file ~/.aws/credentials ubuntu@$master_dns:~/
ssh -i $pem_file ubuntu@$master_dns

# Copy the two lines containing the appropriate credentials (with "export" at the beginning of both lines)
sed -n '6,7p' credentials >> ~/.profile
# cat -n ~/.profile |||||| to see which lines to insert "export" at the beginning of 
sed -i -e '28,29s/^/export /' ~/.profile
source ~/.profile

rm credentials

######## INSTALL PIP ##########
curl -O https://bootstrap.pypa.io/get-pip.py
sudo apt-get install python3-distutils
python3 get-pip.py --user
# make sure ~/.local/bin is stored as an Env Variable in ~/.profile
echo -en '\n' >> ~/.profile
echo 'export PATH=~/.local/bin:$PATH' >> ~/.profile
source ~/.profile
pip -V

######## INSTALL AWS CLI ##########
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

##### INSTALL PYTHON PACKAGES #########
pip install boto3

######### COPY DATA TO S3 ###########
cd chess-platform/
# Remove any old pgn files so we dont accidently append to them
rm -r chess-data/chesscom-db/

# TMUX windows so EC2 can still run after closing your ssh connection
tmux new -s mywindow # Run script here, leave whenever
tmux a -t mywindow   # When you log back in, come here to see progress

# this line to just copy updated PY files
master_dns="ec2-34-222-40-43.us-west-2.compute.amazonaws.com"
scp -r -i $pem_file ./chess-platform/data-ingestion/ChessComCrawl/*.py ubuntu@$master_dns:~/chess-platform/data-ingestion/ChessComCrawl
ssh -i $pem_file ubuntu@$master_dns

# Python glob pattern for user file list
user_list="countries/FR.json"
s3_key="chesscom-db/by-country"
agent="linux-gnu-Python-Requests"
# Run the main script! Calling the listed parameters directly from command line
python3 data-ingestion/ChessComCrawl/pgn-scraper-thread-chunks.py $user_list $s3_key $agent $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY

# View some data in S3 to make sure it looks correct
bucket="erops-chess"
key="chesscom-db/titled-games"
aws s3 cp s3://$bucket/$key/IM-games-0.pgn - | head -n 50
aws s3 ls s3://$bucket/$key --recursive



