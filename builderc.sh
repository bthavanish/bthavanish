#!/bin/bash
set -euo pipefail

REGION="ap-south-1"
NAME_TAG="rom-build"
KEY_NAME="rom-build-key"
KEY_FILE="$HOME/rom-build-key.pem"
SG_NAME="rom-build-sg"

# Good build box without going overboard
INSTANCE_TYPE="c7i.4xlarge"
USE_SPOT="true"

# Current Ubuntu 24.04 LTS AMI from Canonical SSM public parameters
AMI_ID='resolve:ssm:/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id'

BLOCK_DEVICE='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":500,"VolumeType":"gp3","DeleteOnTermination":true}}]'

step() {
  echo
  echo "╔════════════════════════════════════════╗"
  echo "║ $1"
  echo "╚════════════════════════════════════════╝"
  echo
}

get_my_ip() {
  curl -s https://checkip.amazonaws.com | tr -d '\n'
}

get_vpc_id() {
  aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text
}

get_sg_id() {
  aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text
}

ensure_sg() {
  local sg_id
  sg_id="$(get_sg_id)"

  if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
    local vpc_id
    vpc_id="$(get_vpc_id)"
    sg_id="$(
      aws ec2 create-security-group \
        --region "$REGION" \
        --group-name "$SG_NAME" \
        --description "ROM build SSH access" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text
    )"
  fi

  echo "$sg_id"
}

get_existing_instance() {
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$NAME_TAG" "Name=instance-state-name,Values=pending,running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text
}

step "1/4 Checking for existing instance"

INSTANCE_ID="$(get_existing_instance || true)"
if [ -n "${INSTANCE_ID:-}" ] && [ "$INSTANCE_ID" != "None" ]; then
  echo "Using existing instance: $INSTANCE_ID"
else
  step "2/4 Ensuring security group"

  SG_ID="$(ensure_sg)"
  echo "Security group ID: $SG_ID"

  MY_IP="$(get_my_ip)"
  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$MY_IP/32" >/dev/null 2>&1 || true

  step "3/4 Launching instance"

  if [ "$USE_SPOT" = "true" ]; then
    MARKET_OPTS='{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}'
    INSTANCE_ID="$(
      aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --instance-market-options "$MARKET_OPTS" \
        --block-device-mappings "$BLOCK_DEVICE" \
        --count 1 \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG}]" \
        --query 'Instances[0].InstanceId' \
        --output text
    )"
  else
    INSTANCE_ID="$(
      aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --block-device-mappings "$BLOCK_DEVICE" \
        --count 1 \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG}]" \
        --query 'Instances[0].InstanceId' \
        --output text
    )"
  fi

  echo "Instance ID: $INSTANCE_ID"
fi

step "4/4 Waiting and SSHing"

aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$INSTANCE_ID"

PUBLIC_IP="$(
  aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text
)"

chmod 600 "$KEY_FILE"

aws ec2 describe-instances \
  --region ap-south-1 \
  --instance-ids i-04036bb5171885bfd \
  --query 'Reservations[0].Instances[0].[State.Name,PublicIpAddress]' \
  --output table
