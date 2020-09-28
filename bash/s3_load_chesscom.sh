#!/bin/bash
# LOAD DATA FROM CHESS.COM API into S3 (using an AWS EC2 machine)

# Copy the python files to the master, then to the correct worker (must be one level ABOVE the chess project root directory)
# The "./" means current directory, -r means recursive (all files)
#scp -r -i $pem_file chess-platform ubuntu@$master_dns:~/
# this line to just copy updated PY files
scp -r -i $pem_file chess-platform/ChessComCrawl/*.py ubuntu@$master_dns:~/chess-platform/ChessComCrawl
ssh master
#scp -r chess-platform ubuntu@worker2:~/
scp -r chess-platform/ChessComCrawl/*.py ubuntu@worker2:~/chess-platform/ChessComCrawl
exit

# Make sure that the AWS credentials are stored as user environment variables in the ~/.profile file. 
# It seems that we only need to do this on master.
scp -i $pem_file ~/.aws/credentials ubuntu@$master_dns:~/
ssh master
# Copy the two lines containing the appropriate credentials (with "export" at the beginning of both lines)
sed -n '6,7p' credentials >> ~/.profile
# cat -n ~/.profile |||||| to see which lines to insert "export" at the beginning of 
sed -i -e '29,30s/^/export /' ~/.profile
source ~/.profile

# Copy credentials to the worker node we want to use
scp credentials ubuntu@worker2:~/
rm credentials

ssh worker2

######## INSTALL PIP ##########
curl -O https://bootstrap.pypa.io/get-pip.py
sudo apt-get install python3-distutils
python3 get-pip.py --user
# make sure ~/.local/bin is stored as an Env Variable in ~/.profile
echo 'export PATH=~/.local/bin:$PATH' >> ~/.profile
source ~/.profile

######## INSTALL AWS CLI ##########
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

##### INSTALL PYTHON PACKAGES #########
pip install boto3

# Store and call AWS credentials from ~/.profile
sed -n '6,7p' credentials >> ~/.profile
# cat -n ~/.profile |||||| to see which lines to insert "export" at the beginning of 
sed -i -e '30,31s/^/export /' ~/.profile
rm credentials

######### COPY DATA TO S3 ###########
cd chess-platform/
# Remove any old pgn files so we dont accidently append to them
rm -r chess-data/chesscom-db/

source ~/.profile
# Python glob pattern for user file list
user_list="countries/A*.json"
agent="linux-gnu-Python-Requests"
# Run the main script! 
python3 ChessComCrawl/pgn-scraper-thread-chunks.py $user_list $agent $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY

# View some data in S3 to make sure it looks correct
bucket="erops-chess"
key="chesscom-db/by-country"
aws s3 ls s3://$bucket/$key --recursive
aws s3 cp s3://$bucket/$key/AD-games-0.pgn - | head -n 100


