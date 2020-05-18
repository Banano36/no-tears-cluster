#!/usr/bin/env bash -l

# Note the -l above to get .bashrc and /etc/profile

exec &> >(tee -a "/tmp/BOOTSTRAP.log")
shopt -q login_shell && echo 'Login shell' || echo 'Not login shell'

# Force login shell
. /etc/profile

if [ -f /tmp/BOOTSTRAP.WHOAMI ]; then
    echo "bootstrap is already running"
    exit 0
fi

whoami > /tmp/BOOTSTRAP.WHOAMI
env >> /tmp/BOOTSTRAP.WHOAMI

#export VPC_ID=${1:-default}
#export MASTER_SUBNET_ID=${2:-default}
#export COMPUTE_SUBNET_ID=${3:-default}
#export SSH_KEY_ID=${1:-default}
#export PRIVATE_KEY_ARN=${2:-default}

#TODO:
sudo pip-3.6 --disable-pip-version-check --no-cache-dir install aws-parallelcluster --upgrade
#sudo pip-3.6 --disable-pip-version-check --no-cache-dir install aws-parallelcluster --user

export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | rev | cut -c 2- | rev)

# Load the SSH Key generated by CloudFormation
aws secretsmanager get-secret-value --secret-id ${private_key_arn} --query SecretString --output text > ~/.ssh/${ssh_key_id}
chmod 600 ~/.ssh/${ssh_key_id}

# Automatically add ssh key into agent. we need to make the agent stop asking for a password
echo 'eval $(ssh-agent)' >> ~/.bashrc
echo "ssh-add ~/.ssh/${ssh_key_id}" >> ~/.bashrc

mkdir -p ~/.parallelcluster
cat > ~/.parallelcluster/config <<EOF
[global]
cluster_template = hpc
update_check = true
sanity_check = true

[aws]
aws_region_name = ${AWS_DEFAULT_REGION}

[aliases]
ssh = ssh {CFN_USER}@{MASTER_IP} {ARGS}

[cluster hpc]
key_name = ${ssh_key_id}
base_os = ubuntu1804
scheduler = slurm
master_instance_type = c5.2xlarge
compute_instance_type = c5.18xlarge
vpc_settings = public-private
fsx_settings = fsx-scratch2
disable_hyperthreading = true
dcv_settings = dcv
post_install = ${post_install_script_url}
post_install_args = "/shared/spack-0.13 /opt/slurm/log sacct.log"
s3_read_resource = arn:aws:s3:::*
s3_read_write_resource = ${s3_read_write_resource}/*
initial_queue_size = 0
max_queue_size = 10
placement_group = DYNAMIC
master_root_volume_size = 200
compute_root_volume_size = 80
ebs_settings = myebs
cw_log_settings = cw-logs

[ebs myebs]
volume_size = 500
shared_dir = /shared

[dcv mydcv]
enable = master

[fsx fsx-scratch2]
shared_dir = /scratch
storage_capacity = 1200
deployment_type = SCRATCH_2
import_path=${s3_read_write_url}

[dcv dcv]
enable = master
port = 8443
access_from = 0.0.0.0/0

[cw_log cw-logs]
enable = false

[vpc public-private]
vpc_id = ${vpc_id}
master_subnet_id = ${master_subnet_id}
compute_subnet_id = ${compute_subnet_id}

EOF


. ~/.bashrc
. /etc/profile

which pcluster >> /tmp/BOOTSTRAP.WHOAMI

aws configure set default.region ${AWS_DEFAULT_REGION}
aws configure set default.output json

env >> /tmp/BOOTSTRAP.PCLUSTER

pcluster list

# Start the pcluster provisioning, but don't wait for it to complete.
pcluster create -t hpc hpc-cluster -c ~/.parallelcluster/config --nowait -nr

echo "Finished" >> /tmp/BOOTSTRAP.WHOAMI
echo "Finished"
