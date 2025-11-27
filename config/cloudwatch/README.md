# ParallelCluster CloudWatch Monitoring

A comprehensive monitoring solution for distributed training clusters.

## 📋 Table of Contents

- [Quick Start](#Quick-Start)
- [Dashboard Composition](#Dashboard-Composition)
- [Installation Methods](#Installation-Methods)
- [Instance Type-Specific Configuration](#Instance-Type-Specific-Configuration)
- [Collected Metrics](#Collected-Metrics)
- [File Structure](#File-Structure)
- [Dashboard Feature Details](#Dashboard-Feature-Details)
- [Troubleshooting](#Troubleshooting)

## 🚀 Quick Start (3 minutes)

### Step 1: Deploy to S3
```bash
cd parallelcluster-for-llm
source environment-variables-bailey.sh
bash config/cloudwatch/deploy-to-s3.sh
```

### Step 2: Create the Cluster (Fully Automatic)
```bash
pcluster create-cluster \
    --cluster-name ${CLUSTER_NAME} \
    --cluster-configuration cluster-config.yaml
```

**Automatically Performed Actions:**
- ✅ Install CloudWatch Agent (all nodes)
- ✅ Install Slurm metrics collector (HeadNode)
- ✅ Install DCGM/Node Exporter (ComputeNode, GPU mode)
- ✅ **Automatically create the dashboards** (in the background on HeadNode)

### Step 3: Check the Dashboards (1-2 minutes later)

The dashboards are automatically created after the HeadNode starts (takes about 1-2 minutes).

```bash
# Check the dashboard creation log
ssh headnode
tail -f /var/log/dashboard-creation.log
```

**Dashboard URL:**
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards:
```

**Manual Creation (if needed):**
```bash
# Run locally
bash config/cloudwatch/create-dashboard.sh ${CLUSTER_NAME} ${AWS_REGION}
bash config/cloudwatch/create-advanced-dashboard.sh ${CLUSTER_NAME} ${AWS_REGION}
```

## 📊 Dashboard Composition

### Default Dashboard (13 Widgets)
Comprehensive monitoring for both infrastructure managers and model trainers:
- CPU/memory/disk utilization
- Network and FSx Lustre I/O
- Slurm logs (error, resume, suspend)
- GPU monitoring (DCGM)
- Cluster management logs

### Advanced Dashboard (12 Widgets)
Real-time monitoring of Slurm job queue and node status:
- Slurm node status (Total/Idle/Allocated/Down)
- Job queue status (Running/Pending/Total)
- Node utilization calculation
- Job completion/failure logs
- GPU status monitoring

## 🔧 Installation Methods

### Automatic Installation (Recommended)

Installed automatically during cluster creation:

- **HeadNode**: CloudWatch Agent + Slurm metrics collector + Prometheus
- **ComputeNode**: CloudWatch Agent + DCGM Exporter (optional) + Node Exporter (optional)
- **LoginNode**: CloudWatch Agent

### Manual Installation

Can be installed manually if needed:

```bash
# On HeadNode
aws s3 cp s3://${S3_BUCKET}/config/cloudwatch/install-cloudwatch-agent.sh /tmp/
bash /tmp/install-cloudwatch-agent.sh ${CLUSTER_NAME} ${AWS_REGION} ${S3_BUCKET}

aws s3 cp s3://${S3_BUCKET}/config/cloudwatch/install-slurm-metrics.sh /tmp/
bash /tmp/install-slurm-metrics.sh ${CLUSTER_NAME} ${AWS_REGION} ${S3_BUCKET}

# On ComputeNode
aws s3 cp s3://${S3_BUCKET}/config/cloudwatch/install-cloudwatch-agent.sh /tmp/
bash /tmp/install-cloudwatch-agent.sh ${CLUSTER_NAME} ${AWS_REGION} ${S3_BUCKET}
```

## 🔧 Instance Type-Specific Configuration

You can choose which components to install based on the Compute node type.

### Quick Configuration

```bash
# environment-variables-bailey.sh

# GPU instances (p5, p4d, g5, g4dn)
export COMPUTE_SETUP_TYPE="gpu"

# CPU instances (c5, m5, r5)
export COMPUTE_SETUP_TYPE="cpu"

# Minimal setup (for testing)
export COMPUTE_SETUP_TYPE=""
```

| Setting | Installed Items | Monitoring |
|---------|-----------------|------------|
| `"gpu"` | Docker + Pyxis + EFA + DCGM + Node Exporter | ✅ Full |
| `"cpu"` | Docker + Pyxis | ⚠️ CloudWatch only |
| `""` | None | ⚠️ Basic CloudWatch only |

**Detailed Guide**: [Instance Type-Specific Configuration Guide](../../guide/INSTANCE-TYPE-CONFIGURATION.md)

## 📈 Collected Metrics

### CloudWatch Agent (Automatically Collected)
- **CPU**: usage_idle, usage_iowait
- **Memory**: used_percent, available, used
- **Disk**: used_percent, free, used, I/O
- **Network**: tcp_established, tcp_time_wait
- **Swap**: used_percent

### Slurm Metrics (Collected Every Minute)
- **NodesTotal**: Total number of nodes
- **NodesIdle**: Idle nodes
- **NodesAllocated**: Nodes running jobs
- **NodesDown**: Nodes in Down state
- **JobsRunning**: Running jobs
- **JobsPending**: Pending jobs
- **JobsTotal**: Total jobs

### Log Collection (7 Log Groups)
- `/var/log/slurmctld.log` → `/aws/parallelcluster/${CLUSTER_NAME}/slurm`
- `/var/log/slurmd.log` → `/aws/parallelcluster/${CLUSTER_NAME}/slurm`
- `/var/log/parallelcluster/slurm_resume.log` → `/aws/parallelcluster/${CLUSTER_NAME}/slurm-resume`
- `/var/log/parallelcluster/slurm_suspend.log` → `/aws/parallelcluster/${CLUSTER_NAME}/slurm-suspend`
- `/var/log/dcgm/nv-hostengine.log` → `/aws/parallelcluster/${CLUSTER_NAME}/dcgm`
- `/var/log/nvidia-installer.log` → `/aws/parallelcluster/${CLUSTER_NAME}/nvidia`
- `/var/log/parallelcluster/clustermgtd` → `/aws/parallelcluster/${CLUSTER_NAME}/clustermgtd`

## 📁 File Structure

```
config/cloudwatch/
├── README.md                          # This file
├── cloudwatch-agent-config.json       # CloudWatch Agent configuration
├── install-cloudwatch-agent.sh        # CloudWatch Agent installation
├── slurm-metrics-collector.sh         # Slurm metrics collector (cron)
├── install-slurm-metrics.sh           # Slurm metrics collector installation
├── create-dashboard.sh                # Create default dashboard
├── create-advanced-dashboard.sh       # Create advanced dashboard
└── deploy-to-s3.sh                    # S3 deployment script
```

## 🎨 Dashboard Feature Details

### Default Dashboard Widgets

#### 1. Cluster CPU Utilization
- CPU utilization for HeadNode and Compute Nodes
- Detect overload (CPU > 90%)
- 5-minute average

#### 2. Memory Utilization
- Overall node memory utilization
- Detect OOM risk (Memory > 95%)
- Real-time monitoring

#### 3. Slurm Error Logs
- Latest 50 error messages
- Analyze job failure causes
- Real-time updates

#### 4. Network Traffic
- Verify EFA network utilization
- Monitor distributed training communication
- NetworkIn/NetworkOut

#### 5. Disk Utilization
- Warn on disk space shortage (> 85%)
- Track log file growth
- Check checkpoint storage space

#### 6. GPU Monitoring (DCGM)
- Detect GPU errors
- Monitor GPU temperature/power
- GPU memory utilization

#### 7. FSx Lustre I/O
- Shared storage performance
- Dataset loading speed
- Detect bottlenecks

### Advanced Dashboard Widgets

#### 1. Slurm Node Status
```
Total: 10 nodes
Idle: 3 nodes (30%)
Allocated: 6 nodes (60%)
Down: 1 node (10%)
```

#### 2. Slurm Job Queue Status
```
Running: 15 jobs
Pending: 5 jobs (waiting)
Total: 20 jobs
```

#### 3. Node Utilization
- Calculation: `(NodesAllocated / NodesTotal) * 100`
- Target: 70-90% (optimal utilization)
- Analyze cost efficiency

## 🔍 Monitoring Verification

### Verify CloudWatch Agent Status

On HeadNode or ComputeNode:

```bash
# Agent status
sudo systemctl status amazon-cloudwatch-agent

# Agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

### Verify Slurm Metrics

On HeadNode:

```bash
# Metrics collection log
tail -f /var/log/slurm-metrics.log

# Manual test execution
sudo /usr/local/bin/slurm-metrics-collector.sh ${CLUSTER_NAME} ${AWS_REGION}
```

### Verify CloudWatch Metrics

```bash
# Check Slurm metrics
aws cloudwatch get-metric-statistics \
    --namespace "ParallelCluster/${CLUSTER_NAME}/Slurm" \
    --metric-name NodesTotal \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 \
    --statistics Average \
    --region ${AWS_REGION}
```

## 🛠️ Troubleshooting

### Issue: No data on the dashboard

**Resolution:**

1. Verify CloudWatch Agent status:
```bash
ssh headnode
sudo systemctl status amazon-cloudwatch-agent
```

2. Check Slurm metrics collector:
```bash
ssh headnode
tail -f /var/log/slurm-metrics.log
```

3. Verify IAM permissions:
```bash
# Check if the HeadNode IAM role has the CloudWatchAgentServerPolicy
aws iam list-attached-role-policies --role-name <HeadNode-Role-Name>
```

### Issue: Slurm metrics not showing

**Resolution:**

1. Check the Cron job:
```bash
ssh headnode
cat /etc/cron.d/slurm-metrics
```

2. Test manual execution:
```bash
ssh headnode
sudo /usr/local/bin/slurm-metrics-collector.sh ${CLUSTER_NAME} ${AWS_REGION}
```

3. Verify the metrics are sent to CloudWatch:
```bash
aws cloudwatch list-metrics \
    --namespace "ParallelCluster/${CLUSTER_NAME}/Slurm" \
    --region ${AWS_REGION}
```

### Issue: GPU metrics not showing

**Resolution:**

1. Verify DCGM Exporter status:
```bash
ssh compute-node
sudo systemctl status dcgm-exporter
```

2. Check if Prometheus is collecting the metrics:
```bash
ssh headnode
curl http://localhost:9090/api/v1/targets
```

### Issue: Dashboards not auto-generated

**Resolution:**

1. Check the dashboard creation log:
```bash
ssh headnode
tail -f /var/log/dashboard-creation.log
```

2. Manually create the dashboards:
```bash
# Run locally
bash config/cloudwatch/create-dashboard.sh ${CLUSTER_NAME} ${AWS_REGION}
bash config/cloudwatch/create-advanced-dashboard.sh ${CLUSTER_NAME} ${AWS_REGION}
```

## 💡 Tips

### Customizing Dashboards
Modify `create-dashboard.sh` to add your desired metrics

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

### Log Querying
Advanced log analysis with CloudWatch Logs Insights:
```
# Analyze Slurm job failures
fields @timestamp, @message
| filter @message like /FAILED|ERROR/
| stats count() by bin(5m)
```

### Cost Optimization
- Log retention period: 7 days (default, can be changed in `cloudwatch-agent-config.json`)
- Metric collection interval: 60 seconds (adjust as needed)
- Filter out unnecessary logs

## 📚 Related Documentation

- [Instance Type-Specific Configuration Guide](../../guide/INSTANCE-TYPE-CONFIGURATION.md)
- [Cluster Configuration Guide](../README.md)
- [ParallelCluster Monitoring](https://docs.aws.amazon.com/parallelcluster/latest/ug/cloudwatch-logs.html)
- [CloudWatch Agent Configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)
