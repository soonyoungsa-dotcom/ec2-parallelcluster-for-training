#!/bin/bash
# Upload monitoring scripts to S3

set -e

S3_BUCKET="${1}"
REGION="${2:-us-east-2}"

if [ -z "${S3_BUCKET}" ]; then
    echo "Usage: $0 <s3-bucket> [region]"
    echo "Example: $0 my-pcluster-scripts us-east-2"
    exit 1
fi

echo "=== Uploading Monitoring Scripts to S3 ==="
echo "Bucket: s3://${S3_BUCKET}"
echo "Region: ${REGION}"
echo ""

# Check if bucket exists
if ! aws s3 ls "s3://${S3_BUCKET}" --region ${REGION} > /dev/null 2>&1; then
    echo "⚠️  Bucket does not exist. Creating..."
    aws s3 mb "s3://${S3_BUCKET}" --region ${REGION}
fi

# Upload EFA monitoring scripts
echo "Uploading EFA monitoring scripts..."
aws s3 cp config/monitoring/efa_network_monitor.py \
    "s3://${S3_BUCKET}/config/monitoring/efa_network_monitor.py" \
    --region ${REGION}

aws s3 cp config/monitoring/setup-efa-monitoring.sh \
    "s3://${S3_BUCKET}/config/monitoring/setup-efa-monitoring.sh" \
    --region ${REGION}

# Upload CloudWatch dashboard scripts
echo "Uploading CloudWatch dashboard scripts..."
aws s3 cp config/cloudwatch/create-efa-dashboard.sh \
    "s3://${S3_BUCKET}/config/cloudwatch/create-efa-dashboard.sh" \
    --region ${REGION}

# Upload compute node setup script (updated with EFA monitoring)
echo "Uploading compute node setup script..."
aws s3 cp config/compute/setup-compute-node.sh \
    "s3://${S3_BUCKET}/config/compute/setup-compute-node.sh" \
    --region ${REGION}

# Upload head node setup script (updated with EFA dashboard)
echo "Uploading head node setup script..."
aws s3 cp config/headnode/setup-headnode.sh \
    "s3://${S3_BUCKET}/config/headnode/setup-headnode.sh" \
    --region ${REGION}

echo ""
echo "✓ Upload complete!"
echo ""
echo "Uploaded files:"
echo "  - config/monitoring/efa_network_monitor.py"
echo "  - config/monitoring/setup-efa-monitoring.sh"
echo "  - config/cloudwatch/create-efa-dashboard.sh"
echo "  - config/compute/setup-compute-node.sh"
echo "  - config/headnode/setup-headnode.sh"
echo ""
echo "Next steps:"
echo "  1. Update cluster configuration:"
echo "     source environment-variables-bailey.sh"
echo "     envsubst < cluster-config.yaml.template > cluster-config.yaml"
echo ""
echo "  2. Create or update cluster:"
echo "     pcluster create-cluster --cluster-name your-cluster --cluster-configuration cluster-config.yaml"
echo "     # or"
echo "     pcluster update-cluster --cluster-name your-cluster --cluster-configuration cluster-config.yaml"
echo ""
echo "  3. Verify EFA monitoring on compute nodes:"
echo "     pcluster ssh --cluster-name your-cluster -i ~/.ssh/key.pem"
echo "     sudo systemctl status efa-monitor"
echo "     sudo tail -f /var/log/efa_monitor.log"
