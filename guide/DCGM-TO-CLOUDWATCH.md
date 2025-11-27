# How to View DCGM Metrics in CloudWatch

This is a guide on how to view DCGM (NVIDIA Data Center GPU Manager) metrics in CloudWatch.

## 📊 Current Architecture

```
ComputeNode (GPU)
  └─ DCGM Exporter (port 9400)
       └─ Prometheus (HeadNode)
            ├─ Grafana (Visualization)
            └─ AMP (AWS Managed Prometheus)
```

**Problem**: DCGM metrics cannot be viewed in CloudWatch.

## 🎯 Solution Approaches

### Method 1: Direct DCGM to CloudWatch Integration (Recommended)

Scrape DCGM metrics from Prometheus and send them directly to CloudWatch.

#### Installation

```bash
# Run on HeadNode
ssh headnode

# Download script from S3
aws s3 cp s3://${S3_BUCKET}/config/cloudwatch/dcgm-to-cloudwatch.sh /tmp/
chmod +x /tmp/dcgm-to-cloudwatch.sh

# Install
sudo bash /tmp/dcgm-to-cloudwatch.sh ${CLUSTER_NAME} ${AWS_REGION}
```

#### Verification

```bash
# Check service status
sudo systemctl status dcgm-cloudwatch-exporter

# Check logs
sudo journalctl -u dcgm-cloudwatch-exporter -f

# Check CloudWatch metrics
aws cloudwatch list-metrics \
    --namespace "ParallelCluster/${CLUSTER_NAME}/GPU" \
    --region ${AWS_REGION}
```

#### View in CloudWatch

```bash
# Check GPU Utilization
aws cloudwatch get-metric-statistics \
    --namespace "ParallelCluster/${CLUSTER_NAME}/GPU" \
    --metric-name GPUUtilization \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 \
    --statistics Average \
    --region ${AWS_REGION}
```

### Method 2: Add to CloudWatch Dashboard

Add a GPU metrics widget to the existing CloudWatch dashboard.

#### Update Dashboard

```bash
# Fetch current dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "ParallelCluster-${CLUSTER_NAME}" \
    --region ${AWS_REGION} \
    --query 'DashboardBody' \
    --output text > /tmp/dashboard.json

# Manually edit to add GPU widget
# or use an automated script
```

#### GPU Widget JSON

```json
{
    "type": "metric",
    "x": 0,
    "y": 0,
    "width": 12,
    "height": 6,
    "properties": {
        "metrics": [
            [ "ParallelCluster/${CLUSTER_NAME}/GPU", "GPUUtilization", { "stat": "Average" } ],
            [ ".", "GPUMemoryUtilization", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "GPU Utilization",
        "period": 60,
        "yAxis": {
            "left": {
                "min": 0,
                "max": 100
            }
        }
    }
}
```

## 📈 Collected GPU Metrics

### Metrics Provided by DCGM Exporter

| Prometheus Metric | CloudWatch Metric | Unit | Description |
|-------------------|-------------------|------|-------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPUUtilization | Percent | GPU Utilization |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | GPUMemoryUtilization | Percent | GPU Memory Utilization |
| `DCGM_FI_DEV_GPU_TEMP` | GPUTemperature | None | GPU Temperature (°C) |
| `DCGM_FI_DEV_POWER_USAGE` | GPUPowerUsage | None | GPU Power Consumption (W) |
| `DCGM_FI_DEV_FB_USED` | GPUMemoryUsed | Megabytes | Used GPU Memory |
| `DCGM_FI_DEV_FB_FREE` | GPUMemoryFree | Megabytes | Available GPU Memory |

### Dimensions

- `InstanceId`: EC2 Instance ID
- `GPU`: GPU Number (0-7 for p5en.48xlarge)

## 🔄 Automatic Installation (Integrated into HeadNode Setup)

To automatically add the DCGM to CloudWatch integration into the HeadNode setup script:

### 1. Upload Script to S3

```bash
cd parallelcluster-for-llm
aws s3 cp config/cloudwatch/dcgm-to-cloudwatch.sh \
    s3://${S3_BUCKET}/config/cloudwatch/ \
    --region ${AWS_REGION}
```

### 2. Modify setup-headnode.sh

Add the following to `config/headnode/setup-headnode.sh`:

```bash
# Install DCGM to CloudWatch Exporter
(
    set +e
    echo "Installing DCGM to CloudWatch Exporter..."
    
    if [ -n "${S3_BUCKET}" ]; then
        aws s3 cp "s3://${S3_BUCKET}/config/cloudwatch/dcgm-to-cloudwatch.sh" /tmp/ --region ${REGION}
        if [ -f "/tmp/dcgm-to-cloudwatch.sh" ]; then
            chmod +x /tmp/dcgm-to-cloudwatch.sh
            bash /tmp/dcgm-to-cloudwatch.sh "${CLUSTER_NAME}" "${REGION}"
        else
            echo "⚠️  DCGM to CloudWatch exporter script not found"
        fi
    fi
) || echo "⚠️  DCGM to CloudWatch exporter installation failed (non-critical)"
```

### 3. Recreate the Cluster

```bash
# Delete existing cluster
pcluster delete-cluster --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION}

# Create new cluster (DCGM to CloudWatch integration will be installed automatically)
pcluster create-cluster \
    --cluster-name ${CLUSTER_NAME} \
    --cluster-configuration cluster-config.yaml \
    --region ${AWS_REGION}
```

## 📊 CloudWatch Dashboard Example

### GPU Monitoring Dashboard

```json
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "ParallelCluster/${CLUSTER_NAME}/GPU", "GPUUtilization", { "stat": "Average" } ]
                ],
                "title": "GPU Utilization",
                "region": "${AWS_REGION}",
                "period": 60
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "ParallelCluster/${CLUSTER_NAME}/GPU", "GPUTemperature", { "stat": "Maximum" } ]
                ],
                "title": "GPU Temperature",
                "region": "${AWS_REGION}",
                "period": 60,
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "ParallelCluster/${CLUSTER_NAME}/GPU", "GPUPowerUsage", { "stat": "Average" } ]
                ],
                "title": "GPU Power Consumption",
                "region": "${AWS_REGION}",
                "period": 60
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "ParallelCluster/${CLUSTER_NAME}/GPU", "GPUMemoryUsed", { "stat": "Average" } ],
                    [ ".", "GPUMemoryFree", { "stat": "Average" } ]
                ],
                "title": "GPU Memory",
                "region": "${AWS_REGION}",
                "period": 60
            }
        }
    ]
}
```

## 🛠️ Troubleshooting

### Issue: Metrics not appearing in CloudWatch

**Troubleshooting Steps:**

1. Check service status
```bash
sudo systemctl status dcgm-cloudwatch-exporter
```

2. Check logs
```bash
sudo journalctl -u dcgm-cloudwatch-exporter -f
```

3. Verify Prometheus connection
```bash
curl http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL
```

4. Check IAM permissions
```bash
# HeadNode IAM role needs CloudWatch PutMetricData permission
aws iam list-attached-role-policies --role-name <HeadNode-Role>
```

### Issue: Only some GPUs have metrics

**Cause**: DCGM Exporter is running on some ComputeNodes only

**Solution:**
```bash
# Check DCGM Exporter status on all ComputeNodes
srun --nodes=all systemctl status dcgm-exporter
```

### Issue: Metric Latency

**Cause**: Default scrape interval is 60 seconds

**Solution:**
```bash
# Change scrape interval to 30 seconds
sudo systemctl edit dcgm-cloudwatch-exporter

# Add:
[Service]
Environment="SCRAPE_INTERVAL=30"

# Restart
sudo systemctl restart dcgm-cloudwatch-exporter
```

## 💰 Cost Considerations

### CloudWatch Metric Costs

- **Custom Metrics**: $0.30 per metric per month
- **API Requests**: $0.01 per 1,000 GetMetricStatistics requests

### Estimated Cost (p5en.48xlarge x 2 nodes)

- GPU Metrics: 6 x 8 GPUs x 2 nodes = 96 metrics
- Monthly Cost: 96 x $0.30 = **$28.80/month**

### Cost Optimization Tips

1. **Collect Only Necessary Metrics**
```python
# Remove unnecessary metrics in dcgm-to-cloudwatch.sh
DCGM_METRICS = {
    'DCGM_FI_DEV_GPU_UTIL': {...},  # Essential
    'DCGM_FI_DEV_GPU_TEMP': {...},  # Essential
    # 'DCGM_FI_DEV_FB_FREE': {...},  # Remove
}
```

2. **Increase Scrape Interval**
```bash
Environment="SCRAPE_INTERVAL=300"  # 5 minutes
```

## 📚 Related Documentation

- [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [CloudWatch Custom Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
- [Prometheus Python Client](https://github.com/prometheus/client_python)

## 🎯 Summary

### Recommended Method: Direct DCGM to CloudWatch Integration

**Pros:**
- ✅ View GPU metrics in CloudWatch dashboard
- ✅ Set CloudWatch Alarms
- ✅ Easily integrate with other AWS services

**Cons:**
- ⚠️ Additional cost (~$30/month for 2 nodes)
- ⚠️ Slightly delayed (60-second scrape interval)

**Alternatives:**
- Use Grafana only (no cost, real-time)
- Use AMP + AMG (fully managed)
