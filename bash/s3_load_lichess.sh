#!/bin/bash
# LOAD DATA FROM LICHESS.COM into S3

# Install AWS CLI
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version


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

######### COPY DATA INTO S3 ###########
THIS_YEAR="2013"
S3_BUCKET="erops-chess"
S3_KEY="lichess-db"

function transfer_data(){
	THIS_YEAR="2013"
	THIS_URL="https://database.lichess.org/standard/lichess_db_standard_rated_$THIS_YEAR-$THIS_MONTH.pgn"
	THIS_FILE="lichess_db_standard_rated_$THIS_YEAR-$THIS_MONTH.pgn"
	wget $THIS_URL.bz2
	bzip2 -dk $THIS_FILE.bz2
	aws s3 cp $THIS_FILE s3://$S3_BUCKET/$S3_KEY/
	rm -f $THIS_FILE.bz2
	rm -f $THIS_FILE
}

for THIS_MONTH in 05 06 07 08 09 10 11 12
do
  transfer_data $THIS_MONTH
done
