#!/bin/bash
# ============================================================
# AWS EC2 Provisioner for Android ROM Builds
#
# Launches a c5.4xlarge spot instance with 500GB gp3 volume.
# Requires: AWS CLI configured with credentials.
#
# Usage:
#   bash aws/provision.sh          # launch new or reuse existing
#   bash aws/provision.sh destroy  # terminate instance
# ============================================================
set -euo pipefail

REGION="ap-south-1"
NAME_TAG="rom-build"
KEY_NAME="rom-build-key"
KEY_FILE="$HOME/rom-build-key.pem"
SG_NAME="rom-build-sg"
INSTANCE_TYPE="c7i.4xlarge"
USE_SPOT="true"
AMI_ID='resolve:ssm:/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id'
BLOCK_DEVICE='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":500,"VolumeType":"gp3","DeleteOnTermination":true}}]'

step() {
    echo -e "\n╔════════════════════════════════════════╗"
    echo "║ $1"
    echo -e "╚════════════════════════════════════════╝\n"
}

get_my_ip() { curl -s https://checkip.amazonaws.com | tr -d '\n'; }

get_vpc_id() {
    aws ec2 describe-vpcs --region "$REGION" \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text
}

ensure_sg() {
    local sg_id
    sg_id=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

    if [ "$sg_id" = "None" ] || [ -z "$sg_id" ]; then
        sg_id=$(aws ec2 create-security-group --region "$REGION" \
            --group-name "$SG_NAME" --description "ROM build SSH" \
            --vpc-id "$(get_vpc_id)" --query 'GroupId' --output text)
    fi

    aws ec2 authorize-security-group-ingress --region "$REGION" \
        --group-id "$sg_id" --protocol tcp --port 22 \
        --cidr "$(get_my_ip)/32" >/dev/null 2>&1 || true

    echo "$sg_id"
}

get_existing() {
    aws ec2 describe-instances --region "$REGION" \
        --filters "Name=tag:Name,Values=$NAME_TAG" "Name=instance-state-name,Values=pending,running" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None"
}

# ── Destroy ─────────────────────────────────────────────────
if [ "${1:-}" = "destroy" ]; then
    step "Destroying instance"
    INST=$(get_existing)
    [ "$INST" != "None" ] && aws ec2 terminate-instances --region "$REGION" --instance-ids "$INST" && echo "Terminated: $INST" || echo "No instance found"
    exit 0
fi

# ── Create / Reuse ──────────────────────────────────────────
step "1/4 Checking for existing instance"
INST=$(get_existing)
if [ "$INST" != "None" ] && [ -n "$INST" ]; then
    echo "Using existing instance: $INST"
else
    step "2/4 Ensuring security group"
    SG_ID=$(ensure_sg)
    echo "Security group: $SG_ID"

    step "3/4 Launching instance"
    MARKET='{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}'
    INST=$(aws ec2 run-instances --region "$REGION" \
        --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
        --block-device-mappings "$BLOCK_DEVICE" --count 1 \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG}]" \
        ${USE_SPOT:+--instance-market-options "$MARKET"} \
        --query 'Instances[0].InstanceId' --output text)
    echo "Instance ID: $INST"
fi

step "4/4 Waiting for instance"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INST"
aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$INST"

IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INST" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo -e "\n  Instance: $INST"
echo -e "  Public IP: $IP"
echo -e "  SSH: ssh -i $KEY_FILE ubuntu@$IP\n"

chmod 600 "$KEY_FILE" 2>/dev/null || true
