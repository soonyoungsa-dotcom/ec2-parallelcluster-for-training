# ParallelCluster Node-Specific Installation Scripts

These scripts install software tailored to the specific roles of each node type, providing an efficient cluster configuration.

## 📋 Node-Specific Installation Items

### Login Node (for user SSH access)
**Purpose**: Users write code and submit jobs  
**Installed Items**:
- CloudWatch Agent (sends system metrics)
- Basic development tools (vim, git, htop)

**Script**: `config/loginnode/setup-loginnode.sh`

```bash
# Minimal installation for fast boot and low resource usage
apt-get install -y vim git htop
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
```

---

### Head Node (Slurm controller)
**Purpose**: Cluster management + monitoring metric collection  
**Installed Items**:
- CloudWatch Agent (system metrics)
- Slurm controller/scheduler (automatically installed by ParallelCluster)
- Prometheus (collects DCGM metrics from Compute Nodes)

**Script**: `config/headnode/setup-headnode.sh`

```bash
# CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Prometheus (Collect Compute Node metrics)
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xvf prometheus-2.45.0.linux-amd64.tar.gz
mv prometheus-2.45.0.linux-amd64 /opt/prometheus

# Prometheus configuration - EC2 Auto-discovery
cat > /opt/prometheus/prometheus.yml <<EOF
scrape_configs:
  - job_name: 'dcgm'
    ec2_sd_configs:
      - region: us-west-2
        filters:
          - name: tag:aws:parallelcluster:node-type
            values: [Compute]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:9400'
EOF
```

---

### Compute Node (Run actual workloads)
**Purpose**: Run GPU training and inference workloads  
**Installed Items**:
- **Required**:
  - NVIDIA Driver (included in the AMI)
  - CUDA Toolkit
  - NCCL (multi-GPU communication)
  - EFA Driver + libfabric (p4d/p5 high-speed networking)
  - CloudWatch Agent
- **Strongly Recommended**:
  - Docker + NVIDIA Container Toolkit
  - Pyxis/Enroot (Slurm container plugin)
  - DCGM Exporter (GPU metrics → Prometheus)
  - Node Exporter (system metrics → Prometheus)

**Script**: `config/compute/setup-compute-node.sh`

```bash
# Parallel installation to save time
{
    # EFA
    curl -O https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz
    tar -xf aws-efa-installer-latest.tar.gz
    cd aws-efa-installer && ./efa_installer.sh -y -g
} &

{
    # NCCL
    apt-get update
    apt-get install -y libnccl2 libnccl-dev
} &

{
    # Docker + NVIDIA Container Toolkit
    apt-get install -y docker.io
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update && apt-get install -y nvidia-container-toolkit
    systemctl enable docker && systemctl start docker
} &

{
    # CloudWatch Agent
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb
} &

wait

# Docker-dependent items
# Pyxis
cd /tmp
git clone https://github.com/NVIDIA/pyxis.git
cd pyxis && make install

# DCGM Exporter (systemd service)
cat > /etc/systemd/system/dcgm-exporter.service <<EOF
[Unit]
Description=NVIDIA DCGM Exporter
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/docker run --rm --name dcgm-exporter \
  --gpus all --net host \
  nvcr.io/nvidia/k8s/dcgm-exporter:3.1.8-3.1.5-ubuntu22.04
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dcgm-exporter
systemctl start dcgm-exporter
```


---

## 🔄 Data Flow

```
Login Node → CloudWatch Agent → CloudWatch
                                      ↓
Head Node  → CloudWatch Agent → CloudWatch → Grafana
           → Prometheus ←┐                    
                         │
Compute    → CloudWatch Agent → CloudWatch
Nodes      → DCGM (9400) ─────┘
           → Node Exporter (9100) ─┘
```

### Monitoring Ports
- **9090**: Prometheus (Head Node)
- **9100**: Node Exporter (Compute Nodes - system metrics)
- **9400**: DCGM Exporter (Compute Nodes - GPU metrics)
- **3000**: Grafana (separate Monitoring Instance)

---

## 📦 Uploading to S3

Upload the scripts to S3 for use in ParallelCluster CustomActions:

```bash
# Upload the entire config folder
aws s3 sync config/ s3://your-bucket/config/ --region us-east-1

# Verify the upload
aws s3 ls s3://your-bucket/config/ --recursive
```

---

## 🚀 Usage

### 1. Set environment-variables.sh

```bash
# Enable setup for each node type
export ENABLE_LOGINNODE_SETUP="true"    # LoginNode setup
export ENABLE_HEADNODE_SETUP="true"     # HeadNode setup
export ENABLE_COMPUTE_SETUP="true"      # ComputeNode setup

export S3_BUCKET="your-bucket-name"
export CLUSTER_NAME="my-cluster"
export AWS_REGION="us-east-1"
```

### 2. Create cluster configuration

```bash
source environment-variables.sh
envsubst < cluster-config.yaml.template > cluster-config.yaml
```

### 3. Create the cluster

```bash
pcluster create-cluster \
  --cluster-name my-cluster \
  --cluster-configuration cluster-config.yaml
```

---

## ⏱️ Expected Installation Times

| Node Type | Installation Time | Key Items |
|----------|-------------------|----------|
| Login Node | ~2 minutes | CloudWatch + basic tools |
| Head Node | ~5 minutes | CloudWatch + Prometheus |
| Compute Node | ~15-20 minutes | EFA + NCCL + Docker + DCGM (parallel installation) |

---

## 🔍 Troubleshooting

### Check script execution logs

```bash
# Head Node
sudo tail -f /var/log/cfn-init.log
sudo tail -f /var/log/parallelcluster/clustermgtd

# Compute Node
sudo tail -f /var/log/cloud-init-output.log
```

### Check service status

```bash
# Prometheus (Head Node)
sudo systemctl status prometheus
curl http://localhost:9090/-/healthy

# DCGM Exporter (Compute Node)
sudo systemctl status dcgm-exporter
curl http://localhost:9400/metrics

# Node Exporter (Compute Node)
sudo systemctl status node-exporter
curl http://localhost:9100/metrics
```

---

## 📚 References

- [AWS ParallelCluster Documentation](https://docs.aws.amazon.com/parallelcluster/)
- [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [Prometheus EC2 Service Discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#ec2_sd_config)
- [EFA Installer](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html)


---

## 📊 CloudWatch Monitoring

### Comprehensive Dashboard Solution

**Location**: `config/cloudwatch/`

**Purpose**: Real-time monitoring dashboards for infrastructure managers and model trainers

**Key Features**:
- ✅ Real-time system metrics (CPU, memory, disk, network)
- ✅ Slurm job queue and node status monitoring
- ✅ GPU monitoring (DCGM)
- ✅ FSx Lustre I/O performance
- ✅ Log collection and analysis (Slurm, DCGM, cluster management)

### Quick Start (5 minutes)

```bash
# 1. Upload the configuration to S3
cd parallelcluster-for-llm
source environment-variables-bailey.sh
bash config/cloudwatch/deploy-to-s3.sh

# 2. Create/update the cluster (monitoring setup is automatic)
pcluster create-cluster --cluster-name ${CLUSTER_NAME} --cluster-configuration cluster-config.yaml

# 3. Create the dashboards
bash config/cloudwatch/create-dashboard.sh ${CLUSTER_NAME} ${AWS_REGION}
bash config/cloudwatch/create-advanced-dashboard.sh ${CLUSTER_NAME} ${AWS_REGION}
```

### Dashboard Types

**1. Default Dashboard** (`create-dashboard.sh`)
- CPU/memory/disk utilization
- Network and FSx Lustre I/O
- Slurm logs (error, resume, suspend)
- GPU monitoring (DCGM)
- Cluster management logs

**2. Advanced Dashboard** (`create-advanced-dashboard.sh`)
- Slurm node status (Total/Idle/Allocated/Down)
- Job queue status (Running/Pending/Total)
- Node utilization calculation
- Job completion/failure logs
- Real-time GPU status monitoring

### Automatic Installation

Installed automatically during cluster creation:

- **HeadNode**: CloudWatch Agent + Slurm metrics collector + Prometheus
- **ComputeNode**: CloudWatch Agent + DCGM Exporter + Node Exporter
- **LoginNode**: CloudWatch Agent

### File Structure

```
cloudwatch/
├── README.md                          # Full documentation
├── QUICKSTART.md                      # 5-minute quick start guide
├── cloudwatch-agent-config.json       # CloudWatch Agent configuration
├── install-cloudwatch-agent.sh        # CloudWatch Agent installation
├── slurm-metrics-collector.sh         # Slurm metrics collector
├── install-slurm-metrics.sh           # Slurm metrics collector installation
├── create-dashboard.sh                # Create default dashboard
├── create-advanced-dashboard.sh       # Create advanced dashboard (Slurm metrics)
└── deploy-to-s3.sh                    # S3 deployment script
```

### Collected Metrics

**System Metrics** (CloudWatch Agent):
- CPU: utilization, idle, iowait
- Memory: utilization, available, used
- Disk: utilization, I/O (read/write bytes)
- Network: TCP connection status

**Slurm Metrics** (Custom):
- Node status: Total, Idle, Allocated, Down
- Job status: Running, Pending, Total

**Log Collection**:
- `/var/log/slurmctld.log` - Slurm controller
- `/var/log/slurmd.log` - Slurm daemon
- `/var/log/parallelcluster/slurm_resume.log` - Node start
- `/var/log/parallelcluster/slurm_suspend.log` - Node stop
- `/var/log/dcgm/nv-hostengine.log` - GPU monitoring
- `/var/log/nvidia-installer.log` - NVIDIA driver

### Accessing the Dashboards

AWS Console:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards:
```

Or CLI:
```bash
aws cloudwatch list-dashboards --region ${AWS_REGION}
```

### Detailed Documentation

- [cloudwatch/README.md](cloudwatch/README.md) - Full documentation and customization
- [cloudwatch/QUICKSTART.md](cloudwatch/QUICKSTART.md) - 5-minute quick start guide

---

## 🔄 Updated Data Flow

```
Login Node → CloudWatch Agent → CloudWatch Logs/Metrics
                                      ↓
Head Node  → CloudWatch Agent → CloudWatch Logs/Metrics → Dashboard
           → Slurm Metrics    → CloudWatch Metrics
           → Prometheus ←┐                    
                         │
Compute    → CloudWatch Agent → CloudWatch Logs/Metrics
Nodes      → DCGM (9400) ─────┘
           → Node Exporter (9100) ─┘
```

### Monitoring Ports
- **9090**: Prometheus (Head Node)
- **9100**: Node Exporter (Compute Nodes - system metrics)
- **9400**: DCGM Exporter (Compute Nodes - GPU metrics)

---

## 💡 Additional Tips

### CloudWatch Cost Optimization
- Log retention period: 7 days (default, can be changed in `cloudwatch-agent-config.json`)
- Metric collection interval: 60 seconds (adjust as needed)
- Filter out unnecessary logs

### Setting Alarms
Use CloudWatch Alarms to get notifications when thresholds are exceeded:
```bash
aws cloudwatch put-metric-alarm \
    --alarm-name high-cpu-usage \
    --alarm-description "Alert when CPU exceeds 80%" \
    --metric-name CPU_IDLE \
    --namespace "ParallelCluster/${CLUSTER_NAME}" \
    --statistic Average \
    --period 300 \
    --threshold 20 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 2
```

### Log Query Examples
Advanced queries in CloudWatch Logs Insights:
```
# Analyze Slurm job failures
fields @timestamp, @message
| filter @message like /FAILED|ERROR/
| stats count() by bin(5m)

# Monitor GPU temperatures
fields @timestamp, @message
| filter @message like /Temperature/
| parse @message /Temperature: (?<temp>\d+)/
| stats avg(temp) by bin(1m)
```
