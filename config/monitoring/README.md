# EFA Network Monitoring

This directory contains scripts for monitoring EFA (Elastic Fabric Adapter) network performance on GPU compute nodes.

## Files

- `efa_network_monitor.py` - Python script that collects EFA statistics and sends to CloudWatch
- `setup-efa-monitoring.sh` - Installation script that sets up the monitoring service

## Features

- **Lightweight**: <5% CPU, <256MB memory
- **Automatic**: Starts on boot, restarts on failure
- **Batched**: Collects 5 minutes of data before sending to CloudWatch
- **Multi-interface**: Monitors all EFA interfaces
- **Error tracking**: Tracks receive errors and transmit discards

## Metrics Collected

| Metric | Unit | Description |
|--------|------|-------------|
| `rx_bytes_rate` | Bytes/Second | Receive throughput |
| `tx_bytes_rate` | Bytes/Second | Transmit throughput |
| `rx_packets_rate` | Count/Second | Receive packet rate |
| `tx_packets_rate` | Count/Second | Transmit packet rate |
| `rx_errors` | Count | Receive errors |
| `tx_discards` | Count | Transmit discards |

All metrics are published to CloudWatch namespace: `ParallelCluster/Network`

## Installation

EFA monitoring is **automatically installed** on GPU compute nodes when:
1. Instance type has EFA enabled (p4d, p5, p5en)
2. Setup type is "gpu" (5th argument to setup-compute-node.sh)
3. Scripts are uploaded to S3

### Upload to S3

```bash
cd parallelcluster-for-llm
source environment-variables-bailey.sh

# Upload monitoring scripts
aws s3 cp config/monitoring/efa_network_monitor.py s3://${S3_BUCKET}/config/monitoring/
aws s3 cp config/monitoring/setup-efa-monitoring.sh s3://${S3_BUCKET}/config/monitoring/
```

### Manual Installation

If you need to install on an existing compute node:

```bash
# SSH to compute node
pcluster ssh --cluster-name your-cluster -i ~/.ssh/key.pem

# Download scripts
sudo mkdir -p /opt/monitoring
aws s3 cp s3://your-bucket/config/monitoring/efa_network_monitor.py /opt/monitoring/
aws s3 cp s3://your-bucket/config/monitoring/setup-efa-monitoring.sh /tmp/

# Run setup
sudo bash /tmp/setup-efa-monitoring.sh
```

## Service Management

```bash
# Check status
sudo systemctl status efa-monitor

# View logs
sudo tail -f /var/log/efa_monitor.log
sudo journalctl -u efa-monitor -f

# Restart
sudo systemctl restart efa-monitor

# Stop
sudo systemctl stop efa-monitor

# Start
sudo systemctl start efa-monitor
```

## Configuration

Edit `/opt/monitoring/efa_network_monitor.py` to adjust:

```python
COLLECTION_INTERVAL = 60  # Collection interval in seconds
BATCH_SIZE = 5  # Number of intervals before sending to CloudWatch
```

After changes, restart the service:

```bash
sudo systemctl restart efa-monitor
```

## Troubleshooting

### Service not starting

```bash
# Check if EFA interfaces exist
ls -la /sys/class/infiniband/

# Check service logs
sudo journalctl -u efa-monitor -n 50

# Run manually for testing
sudo python3 /opt/monitoring/efa_network_monitor.py
```

### No metrics in CloudWatch

```bash
# Verify IAM permissions
aws cloudwatch put-metric-data \
  --namespace Test \
  --metric-name TestMetric \
  --value 1

# Check if script is running
ps aux | grep efa_network_monitor

# Check logs
sudo tail -100 /var/log/efa_monitor.log
```

## Dashboard

Create CloudWatch dashboard:

```bash
cd parallelcluster-for-llm/config/cloudwatch
bash create-efa-dashboard.sh your-cluster-name us-east-2
```

## Performance Impact

- **CPU**: <5% (systemd enforced with CPUQuota=5%)
- **Memory**: <256MB (systemd enforced with MemoryLimit=256M)
- **Network**: Minimal (batched CloudWatch API calls every 5 minutes)
- **Disk**: <100MB logs (with daily rotation)

## Cost Estimate

For 4 compute nodes with EFA:
- Metrics: 6 metrics × 4 nodes × $0.30/month = $7.20
- API calls: ~17,000 calls/month × $0.01/1000 = $0.17
- **Total**: ~$7.37/month (excluding dashboard)

## Related Documentation

- [EFA Monitoring Guide](../../guide/EFA-MONITORING.md)
- [DCGM Monitoring](../../guide/DCGM-TO-CLOUDWATCH.md)
- [CloudWatch Monitoring](../../guide/MONITORING.md)
