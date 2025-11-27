# Guide to Grafana Dashboard Setup

## Quick Start

A Grafana Workspace has been created, but the dashboard is empty. Use the following methods to add dashboards.

## Method 1: Import Community Dashboards (Recommended ⭐)

### 1. Node Exporter Full (System Metrics)

**In the Grafana UI:**
1. **Dashboards** → **New** → **Import**
2. Enter Dashboard ID: **`1860`**
3. Click **Load**
4. Select Data source: **Amazon Managed Service for Prometheus**
5. Click **Import**

**Included Metrics:**
- ✅ CPU Utilization (Overall, Per-Core)
- ✅ Memory Utilization (Used, Free, Cached)
- ✅ Disk I/O (Read/Write)
- ✅ Network Traffic (In/Out)
- ✅ System Load (1m, 5m, 15m)
- ✅ Filesystem Usage
- ✅ Process Count

**Dashboard Link:** https://grafana.com/grafana/dashboards/1860

---

### 2. NVIDIA DCGM Exporter (GPU Metrics)

**In the Grafana UI:**
1. **Dashboards** → **New** → **Import**
2. Enter Dashboard ID: **`12239`**
3. Click **Load**
4. Select Data source: **Amazon Managed Service for Prometheus**
5. Click **Import**

**Included Metrics:**
- ✅ GPU Utilization (%)
- ✅ GPU Memory Usage (Used/Total)
- ✅ GPU Temperature (°C)
- ✅ GPU Power Usage (W)
- ✅ GPU Clock Speed (MHz)
- ✅ PCIe Throughput (TX/RX)
- ✅ NVLink Throughput
- ✅ GPU Errors

**Dashboard Link:** https://grafana.com/grafana/dashboards/12239

---

### 3. Prometheus Stats (Prometheus Monitoring)

**In the Grafana UI:**
1. **Dashboards** → **New** → **Import**
2. Enter Dashboard ID: **`2`**
3. Click **Load**
4. Select Data source: **Amazon Managed Service for Prometheus**
5. Click **Import**

**Included Metrics:**
- ✅ Prometheus Status
- ✅ Scrape Success Rate
- ✅ Metric Collection Latency
- ✅ Stored Samples

**Dashboard Link:** https://grafana.com/grafana/dashboards/2

---

## Method 2: Import Custom Dashboard

Use the simple dashboard included in this repository.

### ParallelCluster Overview Dashboard

**File Location:** `config/monitoring/parallelcluster-dashboard.json`

**Import Method:**
1. **Dashboards** → **New** → **Import**
2. Click **Upload JSON file**
3. Select `parallelcluster-dashboard.json`
4. Select Data source: **Amazon Managed Service for Prometheus**
5. Click **Import**

**Included Panels:**
- CPU Usage (All Nodes)
- Memory Usage (All Nodes)
- GPU Utilization (All GPUs)
- GPU Temperature (All GPUs)
- Active Compute Nodes (Count)
- Total GPUs (Count)

---

## Method 3: Build Your Own Dashboard

### Create a New Dashboard

1. **Dashboards** → **New Dashboard**
2. Click **Add visualization**
3. Select Data source: **Amazon Managed Service for Prometheus**
4. Enter the query (see example queries below)
5. Click **Apply**

### Useful PromQL Query Examples

#### System Metrics

```promql
# CPU Utilization (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory Utilization (%)
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# Disk Utilization (%)
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Network Receive (bytes/s)
rate(node_network_receive_bytes_total{device!="lo"}[5m])

# Network Transmit (bytes/s)
rate(node_network_transmit_bytes_total{device!="lo"}[5m])

# System Load (1 minute average)
node_load1

# Active Nodes Count
count(up{job="compute-nodes"} == 1)
```

#### GPU Metrics

```promql
# GPU Utilization (%)
DCGM_FI_DEV_GPU_UTIL

# GPU Memory Utilization (%)
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE) * 100

# GPU Temperature (°C)
DCGM_FI_DEV_GPU_TEMP

# GPU Power Consumption (W)
DCGM_FI_DEV_POWER_USAGE

# GPU Memory Used (MB)
DCGM_FI_DEV_FB_USED

# GPU Clock Speed (MHz)
DCGM_FI_DEV_SM_CLOCK

# Total GPU Count
count(DCGM_FI_DEV_GPU_UTIL)

# Average GPU Utilization per GPU
avg by (gpu, instance) (DCGM_FI_DEV_GPU_UTIL)
```

#### Prometheus Metrics

```promql
# Scrape Success Rate
rate(prometheus_target_scrapes_sample_out_of_order_total[5m])

# Collected Samples
rate(prometheus_tsdb_head_samples_appended_total[5m])

# Active Targets
count(up == 1)

# Failed Targets
count(up == 0)
```

---

## Troubleshooting When Data is Missing

### 1. Verify Cluster is Created

```bash
pcluster describe-cluster --cluster-name YOUR_CLUSTER_NAME
```

**The Status should be `CREATE_COMPLETE`.**

### 2. Check Prometheus Status on the HeadNode

```bash
# SSH to the HeadNode
pcluster ssh --cluster-name YOUR_CLUSTER_NAME -i ~/.ssh/key.pem

# Check Prometheus status
sudo systemctl status prometheus

# Check Prometheus logs
sudo journalctl -u prometheus -n 50

# Verify remote_write configuration
grep -A 10 "remote_write" /etc/prometheus/prometheus.yml
```

### 3. Verify ComputeNodes are Running

```bash
# Check Slurm node status
sinfo

# Expected output:
# PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
# gpu          up   infinite      2   idle compute-dy-gpu-[1-2]
```

### 4. Query Directly in Grafana Explore

**In the Grafana UI:**
1. Click **Explore (🔍)** menu
2. Select Data source: **Amazon Managed Service for Prometheus**
3. Enter Query: `up`
4. Click **Run query**

**Expected Result:**
```
up{instance=**********0:9100", job="compute-nodes"} 1
up{instance=**********1:9100", job="compute-nodes"} 1
up{instance=**********0:9400", job="dcgm"} 1
up{instance=**********1:9400", job="dcgm"} 1
```

**If `up` value is 1, it's normal; if 0, there's an issue.**

---

## Alert Setup (Optional)

### Create an SNS Topic

```bash
# Create SNS Topic
aws sns create-topic --name pcluster-alerts --region YOUR_REGION

# Subscribe by email
aws sns subscribe \
  --topic-arn arn:aws:sns:YOUR_REGION:YOUR_ACCOUNT:pcluster-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com

# Check email (click "Confirm subscription" in the received email)
```

### Set up Grafana Alert Channel

**In the Grafana UI:**
1. **Alerting** → **Notification channels** → **New channel**
2. **Name**: `SNS Alerts`
3. **Type**: `AWS SNS`
4. **Topic ARN**: `arn:aws:sns:YOUR_REGION:YOUR_ACCOUNT:pcluster-alerts`
5. **Auth Provider**: `AWS SDK Default`
6. **Save**

### Example Alert Rules

**GPU Temperature Alert:**
```promql
DCGM_FI_DEV_GPU_TEMP > 85
```

**Node Down Alert:**
```promql
up{job="compute-nodes"} == 0
```

**High Memory Utilization Alert:**
```promql
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 90
```

**GPU Memory Pressure Alert:**
```promql
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE) * 100 > 95
```

---

## Additional Resources

### Search for Community Dashboards

- **Grafana Dashboards**: https://grafana.com/grafana/dashboards/
- **Search Keywords**: `node exporter`, `nvidia`, `dcgm`, `gpu`, `prometheus`

### Recommended Dashboards

| Dashboard | ID | Description |
|-----------|-----|------------|
| Node Exporter Full | 1860 | Comprehensive system metrics |
| NVIDIA DCGM Exporter | 12239 | GPU metrics |
| Prometheus Stats | 2 | Prometheus self-monitoring |
| Node Exporter for Prometheus | 11074 | Simple system metrics |
| NVIDIA GPU Metrics | 14574 | Alternative GPU dashboard |

### Documentation

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [PromQL Guide](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [DCGM Exporter Metrics](https://docs.nvidia.com/datacenter/dcgm/latest/dcgm-api/dcgm-api-field-ids.html)
- [Node Exporter Metrics](https://github.com/prometheus/node_exporter#enabled-by-default)

---

## Summary

**Quick Start (3 minutes):**
1. Access Grafana
2. Import Dashboard ID `1860` (System Metrics)
3. Import Dashboard ID `12239` (GPU Metrics)
4. You're done! 🎉

**If no data is visible:**
- Verify the cluster is created
- Ensure HeadNode and ComputeNodes are running
- Wait 5-10 minutes for data collection to start
