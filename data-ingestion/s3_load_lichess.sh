#!/bin/bash
# LOAD DATA FROM LICHESS.COM into S3

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

# Make sure that the AWS credentials are stored as user environment variables in the ~/.profile file. 
# It seems that we only need to do this on master.
scp -i $pem_file ~/.aws/credentials ubuntu@$master_dns:~/
ssh -i $pem_file ubuntu@$master_dns
# Copy the two lines containing the appropriate credentials (with "export" at the beginning of both lines)
sed -n '6,7p' credentials >> ~/.profile
# cat -n ~/.profile |||||| to see which lines to insert "export" at the beginning of 
sed -i -e '28,29s/^/export /' ~/.profile
source ~/.profile
rm credentials

# Install AWS CLI
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# TMUX windows so EC2 can still run after closing your ssh connection
tmux new -s mywindow # Run script here, leave whenever
tmux a -t mywindow   # When you log back in, come here to see progress

######### COPY DATA INTO S3 ###########
THIS_YEAR="2020"
S3_BUCKET="erops-chess"
S3_KEY="lichess-db"
THIS_MONTH="05"

function transfer_data(){
	THIS_URL="https://database.lichess.org/standard/lichess_db_standard_rated_$THIS_YEAR-$THIS_MONTH.pgn"
	THIS_FILE="lichess_db_standard_rated_$THIS_YEAR-$THIS_MONTH.pgn"
	wget $THIS_URL.bz2
	bzip2 -dk $THIS_FILE.bz2
	aws s3 cp $THIS_FILE s3://$S3_BUCKET/$S3_KEY/
	rm -f $THIS_FILE.bz2
	rm -f $THIS_FILE
}

for THIS_MONTH in 01 02 03 04 05 06 07 08 09 10 11 12
do
  transfer_data $THIS_MONTH
done

aws s3 cp s3://$S3_BUCKET/$S3_KEY/lichess_db_standard_rated_2020-01.pgn - | head -n 100
