# Quick Start Guide to EFA Network Monitoring

## Overview

EFA (Elastic Fabric Adapter) network monitoring tracks the real-time communication performance between GPU instances.

## Automatic Installation

EFA monitoring is **automatically installed on GPU compute nodes**. No additional setup is required.

### Installation Prerequisites

- ✅ Instance Type: EFA-enabled (p4d, p5, p5en)
- ✅ Setup Type: `gpu` (5th argument)
- ✅ Scripts uploaded to S3

## Deployment Steps

### 1. Upload Scripts

```bash
cd parallelcluster-for-llm
source environment-variables-bailey.sh

# Upload monitoring scripts
bash scripts/upload-monitoring-scripts.sh ${S3_BUCKET} ${REGION}
```

### 2. Create Cluster Configuration

```bash
# Generate config from template
envsubst < cluster-config.yaml.template > cluster-config.yaml
```

### 3. Create or Update Cluster

```bash
# Create new cluster
pcluster create-cluster \
  --cluster-name ${CLUSTER_NAME} \
  --cluster-configuration cluster-config.yaml

# Update existing cluster
pcluster update-cluster \
  --cluster-name ${CLUSTER_NAME} \
  --cluster-configuration cluster-config.yaml
```

### 4. Verification

```bash
# SSH to a compute node
pcluster ssh --cluster-name ${CLUSTER_NAME} -i ~/.ssh/${KEY_PAIR_NAME}.pem

# Check EFA monitoring service status
sudo systemctl status efa-monitor

# View real-time logs
sudo tail -f /var/log/efa_monitor.log

# Example output:
# rdmap0s6: RX=125.34 Mbps, TX=98.21 Mbps
```

## Metric Visibility

### CloudWatch Metrics

```bash
# List available metrics
aws cloudwatch list-metrics \
  --namespace ParallelCluster/Network \
  --region ${REGION}

# Query a specific metric
aws cloudwatch get-metric-statistics \
  --namespace ParallelCluster/Network \
  --metric-name rx_bytes_rate \
  --dimensions Name=InstanceId,Value=i-1234567890abcdef0 \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 60 \
  --statistics Average \
  --region ${REGION}
```

### CloudWatch Dashboard

The dashboard is automatically created during HeadNode initialization:

```bash
# Check dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=ParallelCluster-${CLUSTER_NAME}-EFA"
```

Or create it manually:

```bash
cd parallelcluster-for-llm/config/cloudwatch
bash create-efa-dashboard.sh ${CLUSTER_NAME} ${REGION}
```

## Collected Metrics

| Metric | Unit | Description |
|--------|------|-------------|
| `rx_bytes_rate` | Bytes/Second | Receive Throughput |
| `tx_bytes_rate` | Bytes/Second | Transmit Throughput |
| `rx_packets_rate` | Count/Second | Receive Packet Rate |
| `tx_packets_rate` | Count/Second | Transmit Packet Rate |
| `rx_errors` | Count | Receive Errors (cumulative) |
| `tx_discards` | Count | Transmit Discards (cumulative) |

## Performance Baseline

### p5en.48xlarge

- **EFA Bandwidth**: 3200 Gbps (400 GB/s)
- **EFA Interfaces**: 32x 100 Gbps
- **Expected Throughput**:
  - NCCL All-Reduce: ~2800 Gbps
  - Point-to-point: ~3000 Gbps

### Validation

```bash
# Check EFA utilization during training
sudo tail -f /var/log/efa_monitor.log

# Expected output (during training):
# rdmap0s6: RX=2500.00 Mbps, TX=2500.00 Mbps  ← High throughput
# rdmap0s6: RX=0.00 Mbps, TX=0.00 Mbps        ← Idle state

# Verify errors (should be 0)
grep -E "rx_errors|tx_discards" /var/log/efa_monitor.log
```

## Troubleshooting

### Service Doesn't Start

```bash
# Check detailed logs
sudo journalctl -u efa-monitor -n 50

# Verify EFA interface
ls -la /sys/class/infiniband/

# Manual execution (for testing)
sudo python3 /opt/monitoring/efa_network_monitor.py
```

### No Metrics in CloudWatch

```bash
# Check IAM permissions
aws cloudwatch put-metric-data \
  --namespace Test \
  --metric-name TestMetric \
  --value 1

# Verify script execution
ps aux | grep efa_network_monitor

# Check logs
sudo tail -100 /var/log/efa_monitor.log
```

### High CPU Usage

The script should normally use less than 5% CPU. If it's high:

```bash
# Check collection interval (should be 60 seconds)
grep COLLECTION_INTERVAL /opt/monitoring/efa_network_monitor.py

# Restart the service
sudo systemctl restart efa-monitor
```

## Cost Considerations

### Expected Monthly Cost (4 Nodes)

- **Metrics**: 6 x 4 nodes x $0.30 = $7.20
- **API Calls**: ~17,000 x $0.01/1000 = $0.17
- **Dashboard**: $3.00
- **Total**: ~$10.37/month

### Cost Optimization

```bash
# Increase collection interval (reduce API calls)
sudo vim /opt/monitoring/efa_network_monitor.py
# COLLECTION_INTERVAL = 300  # Change to 5 minutes

# Increase batch size
# BATCH_SIZE = 10  # Change to 10 minutes

# Restart the service
sudo systemctl restart efa-monitor
```

## Service Management

```bash
# Check status
sudo systemctl status efa-monitor

# Start
sudo systemctl start efa-monitor

# Stop
sudo systemctl stop efa-monitor

# Restart
sudo systemctl restart efa-monitor

# Enable autostart at boot
sudo systemctl enable efa-monitor

# Disable autostart at boot
sudo systemctl disable efa-monitor

# View logs
sudo journalctl -u efa-monitor -f
sudo tail -f /var/log/efa_monitor.log
```

## Integrated Monitoring

EFA monitoring works alongside other monitoring tools:

- **DCGM Exporter**: GPU metrics (port 9400)
- **Node Exporter**: System metrics (port 9100)
- **CloudWatch Agent**: System + custom metrics
- **Prometheus**: Metric aggregation (HeadNode)

All metrics are available in:
- CloudWatch (AWS Console)
- Prometheus (self-hosting mode)
- Grafana (when using AMG)

## Related Documentation

- [Detailed EFA Monitoring Guide](guide/EFA-MONITORING.md)
- [DCGM Monitoring](guide/DCGM-TO-CLOUDWATCH.md)
- [NVLink Monitoring](guide/NVLINK-MONITORING.md)
- [CloudWatch Monitoring](guide/MONITORING.md)

## References

- [AWS EFA Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html)
- [EFA Performance](https://aws.amazon.com/hpc/efa/)
- [NCCL with EFA](https://github.com/aws/aws-ofi-nccl)
