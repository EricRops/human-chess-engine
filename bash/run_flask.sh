export AWS_PROFILE=insight
pem_file="~/.ssh/eric-rops-IAM-keypair.pem"
type="m5a.large"

# Get master DNS string
master_dns=$(aws ec2 describe-instances \
--query 'Reservations[*].Instances[?AmiLaunchIndex==`0`].[PublicDnsName]' \
--filters Name=instance-state-name,Values=running Name=instance-type,Values=$type \
--output text)

# Copy the app files to EC2
#scp -r -i $pem_file ./app ubuntu@$master_dns:~/
scp -r -i $pem_file ./app/*.py ubuntu@$master_dns:~/app/

# SSH into the EC2 machine to host the app
ssh -i $pem_file ubuntu@$master_dns

# Setup Python Virtual Env and run the app!
cd ./app
sudo apt-get update
sudo apt-get install python3-venv

# TMUX windows so EC2 can still run after closing your ssh connection
tmux new -s mywindow # Run script here, leave whenever
tmux a -t mywindow   # When you log back in, come here to see progress

sudo su -
cd /home/ubuntu/app/
python3 -m venv venv
. venv/bin/activate
# pip install -r requirements.txt
export FLASK_APP=flask_app.py
export FLASK_DEBUG=1
flask run --host=0.0.0.0 --port=80

# Kill the process
ps -ef
sudo kill PID 
