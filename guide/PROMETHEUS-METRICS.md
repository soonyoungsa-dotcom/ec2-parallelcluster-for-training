# Guide to Prometheus Collected Metrics

This is a detailed guide on all the metrics collected by the Prometheus instance running on the ParallelCluster HeadNode.

## 📊 Metric Collection Architecture

```
ComputeNode (GPU Mode)
├── DCGM Exporter (port 9400)
│   └── GPU Metrics → Prometheus
└── Node Exporter (port 9100)
    └── System Metrics → Prometheus

HeadNode
└── Prometheus (port 9090)
    ├── Local Storage (self-hosting)
    └── AMP remote_write (amp-only, amp+amg)
```

## 🎮 DCGM Exporter Metrics (GPU)

**Job Name**: `dcgm`  
**Port**: 9400  
**Scrape Interval**: 15 seconds

### GPU Utilization
```promql
# GPU Utilization (0-100%)
DCGM_FI_DEV_GPU_UTIL{gpu="0", instance_id="i-xxxxx"}

# Example Query: Average GPU Utilization
avg(DCGM_FI_DEV_GPU_UTIL)

# Example Query: Per-GPU Utilization
DCGM_FI_DEV_GPU_UTIL{gpu="0"}
```

### GPU Memory
```promql
# GPU Memory Utilization (0-100%)
DCGM_FI_DEV_MEM_COPY_UTIL{gpu="0"}

# GPU Memory Used (MB)
DCGM_FI_DEV_FB_USED{gpu="0"}

# GPU Memory Available (MB)
DCGM_FI_DEV_FB_FREE{gpu="0"}

# Example Query: Total GPU Memory Used
sum(DCGM_FI_DEV_FB_USED)
```

### GPU Temperature
```promql
# GPU Temperature (°C)
DCGM_FI_DEV_GPU_TEMP{gpu="0"}

# Example Query: Maximum Temperature
max(DCGM_FI_DEV_GPU_TEMP)

# Example Query: Temperature Warning (> 85°C)
DCGM_FI_DEV_GPU_TEMP > 85
```

### GPU Power
```promql
# GPU Power Consumption (W)
DCGM_FI_DEV_POWER_USAGE{gpu="0"}

# Example Query: Total Power Consumption
sum(DCGM_FI_DEV_POWER_USAGE)

# Example Query: Average Power Consumption (5 minutes)
avg_over_time(DCGM_FI_DEV_POWER_USAGE[5m])
```

### GPU Clocks
```promql
# SM (Streaming Multiprocessor) Clock (MHz)
DCGM_FI_DEV_SM_CLOCK{gpu="0"}

# Memory Clock (MHz)
DCGM_FI_DEV_MEM_CLOCK{gpu="0"}
```

### GPU Errors
```promql
# ECC Errors (Single-bit)
DCGM_FI_DEV_ECC_SBE_VOL_TOTAL{gpu="0"}

# ECC Errors (Double-bit)
DCGM_FI_DEV_ECC_DBE_VOL_TOTAL{gpu="0"}

# XID Errors
DCGM_FI_DEV_XID_ERRORS{gpu="0"}
```

### GPU PCIe
```promql
# PCIe Tx Throughput (KB/s)
DCGM_FI_DEV_PCIE_TX_THROUGHPUT{gpu="0"}

# PCIe Rx Throughput (KB/s)
DCGM_FI_DEV_PCIE_RX_THROUGHPUT{gpu="0"}

# PCIe Replay Counter
DCGM_FI_DEV_PCIE_REPLAY_COUNTER{gpu="0"}
```

### NVLINK (H100)
```promql
# NVLINK Bandwidth Utilization
DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL{gpu="0"}

# NVLINK Errors
DCGM_FI_PROF_NVLINK_RX_BYTES{gpu="0"}
DCGM_FI_PROF_NVLINK_TX_BYTES{gpu="0"}
```

## 🖥️ Node Exporter Metrics (System)

**Job Name**: `compute-nodes`  
**Port**: 9100  
**Scrape Interval**: 15 seconds

### CPU
```promql
# CPU Time (seconds)
node_cpu_seconds_total{mode="idle", instance_id="i-xxxxx"}
node_cpu_seconds_total{mode="user"}
node_cpu_seconds_total{mode="system"}
node_cpu_seconds_total{mode="iowait"}

# Example Query: CPU Utilization (%)
100 - (avg by (instance_id) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Example Query: Per-Core CPU Utilization
rate(node_cpu_seconds_total{mode!="idle"}[5m])
```

### Memory
```promql
# Total Memory (bytes)
node_memory_MemTotal_bytes

# Available Memory (bytes)
node_memory_MemAvailable_bytes

# Used Memory (bytes)
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Example Query: Memory Utilization (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Buffers/Cached
node_memory_Buffers_bytes
node_memory_Cached_bytes

# Swap
node_memory_SwapTotal_bytes
node_memory_SwapFree_bytes
```

### Disk
```promql
# Disk Used Space (bytes)
node_filesystem_size_bytes{mountpoint="/"}
node_filesystem_avail_bytes{mountpoint="/"}
node_filesystem_used_bytes{mountpoint="/"}

# Example Query: Disk Utilization (%)
(node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"} * 100

# FSx Lustre
node_filesystem_size_bytes{mountpoint="/fsx"}
node_filesystem_avail_bytes{mountpoint="/fsx"}
```

### Disk I/O
```promql
# Read Bytes (bytes)
rate(node_disk_read_bytes_total[5m])

# Write Bytes (bytes)
rate(node_disk_written_bytes_total[5m])

# I/O Time (seconds)
rate(node_disk_io_time_seconds_total[5m])

# Example Query: Disk Throughput (MB/s)
rate(node_disk_read_bytes_total[5m]) / 1024 / 1024
rate(node_disk_written_bytes_total[5m]) / 1024 / 1024
```

### Network
```promql
# Receive Bytes (bytes)
rate(node_network_receive_bytes_total{device="eth0"}[5m])

# Transmit Bytes (bytes)
rate(node_network_transmit_bytes_total{device="eth0"}[5m])

# Example Query: Network Bandwidth (Mbps)
rate(node_network_receive_bytes_total{device="eth0"}[5m]) * 8 / 1000000
rate(node_network_transmit_bytes_total{device="eth0"}[5m]) * 8 / 1000000

# Errors and Drops
node_network_receive_errs_total
node_network_transmit_errs_total
node_network_receive_drop_total
node_network_transmit_drop_total
```

### System Load
```promql
# Load Average
node_load1   # 1-minute average
node_load5   # 5-minute average
node_load15  # 15-minute average

# Example Query: Load per CPU Core
node_load5 / count(node_cpu_seconds_total{mode="idle"})
```

### Processes
```promql
# Running Processes
node_procs_running

# Blocked Processes
node_procs_blocked

# Total Processes
node_processes_state{state="running"}
node_processes_state{state="sleeping"}
node_processes_state{state="zombie"}
```

### System Information
```promql
# Boot Time (Unix timestamp)
node_boot_time_seconds

# Example Query: Uptime (hours)
(time() - node_boot_time_seconds) / 3600

# Context Switches
rate(node_context_switches_total[5m])

# Interrupts
rate(node_intr_total[5m])
```

## 📈 Useful PromQL Query Examples

### GPU Monitoring

#### 1. Overall GPU Utilization
```promql
# Average GPU Utilization
avg(DCGM_FI_DEV_GPU_UTIL)

# Per-Node Average GPU Utilization
avg by (instance_id) (DCGM_FI_DEV_GPU_UTIL)

# Per-GPU Utilization
DCGM_FI_DEV_GPU_UTIL
```

#### 2. GPU Memory Utilization
```promql
# GPU Memory Utilization (%)
(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)) * 100

# Total GPU Memory Used per Node
sum by (instance_id) (DCGM_FI_DEV_FB_USED)
```

#### 3. GPU Temperature Warning
```promql
# GPUs with Temperature > 85°C
DCGM_FI_DEV_GPU_TEMP > 85

# Maximum Temperature
max(DCGM_FI_DEV_GPU_TEMP)
```

#### 4. GPU Power Consumption
```promql
# Total Power Consumption (W)
sum(DCGM_FI_DEV_POWER_USAGE)

# Per-Node Power Consumption
sum by (instance_id) (DCGM_FI_DEV_POWER_USAGE)

# 5-minute Average Power Consumption
avg_over_time(sum(DCGM_FI_DEV_POWER_USAGE)[5m:])
```

### System Monitoring

#### 1. CPU Utilization
```promql
# Overall CPU Utilization (%)
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Per-Node CPU Utilization
100 - (avg by (instance_id) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

#### 2. Memory Utilization
```promql
# Memory Utilization (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Used Memory (GB)
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024
```

#### 3. Disk I/O
```promql
# Read Throughput (MB/s)
rate(node_disk_read_bytes_total[5m]) / 1024 / 1024

# Write Throughput (MB/s)
rate(node_disk_written_bytes_total[5m]) / 1024 / 1024

# Total I/O Throughput
(rate(node_disk_read_bytes_total[5m]) + rate(node_disk_written_bytes_total[5m])) / 1024 / 1024
```

#### 4. Network Bandwidth
```promql
# Receive Bandwidth (Mbps)
rate(node_network_receive_bytes_total{device="eth0"}[5m]) * 8 / 1000000

# Transmit Bandwidth (Mbps)
rate(node_network_transmit_bytes_total{device="eth0"}[5m]) * 8 / 1000000

# EFA Network (p5 instances)
rate(node_network_receive_bytes_total{device=~"efa.*"}[5m]) * 8 / 1000000
```


### Distributed Training Monitoring

#### 1. Multi-Node GPU Utilization
```promql
# Average GPU Utilization across all nodes
avg(DCGM_FI_DEV_GPU_UTIL)

# Per-Node GPU Utilization (8 GPUs per node)
avg by (instance_id) (DCGM_FI_DEV_GPU_UTIL)

# GPU Utilization Spread (Standard Deviation)
stddev(DCGM_FI_DEV_GPU_UTIL)
```

#### 2. Network Communication (All-Reduce)
```promql
# Inter-node Network Traffic
sum(rate(node_network_transmit_bytes_total[5m]))

# NVLINK Bandwidth (Intra-node GPU Communication)
sum(DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL)
```

#### 3. Detecting Training Bottlenecks
```promql
# Nodes with low GPU Utilization (< 50%)
DCGM_FI_DEV_GPU_UTIL < 50

# Nodes with high CPU I/O Wait (> 20%)
rate(node_cpu_seconds_total{mode="iowait"}[5m]) * 100 > 20

# Nodes with Memory Pressure (> 90%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
```

## 🎯 Grafana Dashboard Examples

### GPU Dashboard Panels

#### Panel 1: GPU Utilization
```promql
# Query
avg(DCGM_FI_DEV_GPU_UTIL)

# Visualization: Gauge
# Thresholds: 
#   - Green: 0-70
#   - Yellow: 70-90
#   - Red: 90-100
```

#### Panel 2: GPU Memory
```promql
# Query
sum(DCGM_FI_DEV_FB_USED) / 1024  # GB

# Visualization: Time series
# Unit: GB
```

#### Panel 3: GPU Temperature
```promql
# Query
max(DCGM_FI_DEV_GPU_TEMP)

# Visualization: Stat
# Thresholds:
#   - Green: 0-75
#   - Yellow: 75-85
#   - Red: 85-100
```

#### Panel 4: GPU Power
```promql
# Query
sum(DCGM_FI_DEV_POWER_USAGE)

# Visualization: Time series
# Unit: Watt
```

### System Dashboard Panels

#### Panel 1: CPU Utilization
```promql
# Query
100 - (avg by (instance_id) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Visualization: Time series
# Legend: {{instance_id}}
```

#### Panel 2: Memory Utilization
```promql
# Query
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Visualization: Gauge
```

#### Panel 3: Network I/O
```promql
# Query A (Receive)
rate(node_network_receive_bytes_total{device="eth0"}[5m]) * 8 / 1000000

# Query B (Transmit)
rate(node_network_transmit_bytes_total{device="eth0"}[5m]) * 8 / 1000000

# Visualization: Time series
# Unit: Mbps
```

## 📚 Metric Retention Policies

### Self-Hosting
- **Local Storage**: 15 days (default)
- **Configuration**: `/opt/prometheus/prometheus.yml`
- **Change**: `--storage.tsdb.retention.time=30d`

### AMP (amp-only, amp+amg)
- **Local Storage**: 1 hour (temporary)
- **AMP Storage**: 150 days (automatic)
- **Cost**: Depends on storage usage

## 🔍 Metric Verification

### Prometheus UI
```bash
# On the HeadNode
curl http://localhost:9090/api/v1/targets

# In the browser (port forwarding required)
ssh -L 9*********host:9090 headnode
# http://localhost:9090
```

### PromQL Queries
```bash
# List available metrics
curl http://localhost:9090/api/v1/label/__name__/values

# Query a specific metric
curl 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL'
```

### Grafana Explore
1. Grafana → Explore
2. Data source: Amazon Managed Prometheus
3. Browse metric in the Metric browser
4. Run the query

## 📊 Summary

### GPU Metrics (DCGM)
- ✅ Utilization, Memory, Temperature, Power
- ✅ Clocks, PCIe, NVLINK
- ✅ ECC Errors, XID Errors
- **Total**: ~50 metrics

### System Metrics (Node Exporter)
- ✅ CPU, Memory, Disk, Network
- ✅ Load, Processes, I/O
- **Total**: ~200 metrics

### Collection Interval
- **Scrape interval**: 15 seconds
- **Evaluation interval**: 15 seconds
- **Remote write**: 30 seconds (AMP)

### Expected Storage Capacity
- **Per Node**: ~1-2 MB/hour
- **10 Nodes**: ~10-20 MB/hour
- **Monthly**: ~7-15 GB/month
