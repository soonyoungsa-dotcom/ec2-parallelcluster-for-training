# Guide to Monitor ComputeNode Installation Progress

## Overview

ComputeNode installation takes about 15-20 minutes, and the following components are installed sequentially:
1. EFA Driver (5-10 minutes)
2. Docker + NVIDIA Container Toolkit (3 minutes)
3. Pyxis (2 minutes)
4. CloudWatch Agent (1 minute)
5. DCGM Exporter (1 minute)
6. Node Exporter (1 minute)
7. NCCL Configuration (5 seconds, if applicable)

## 🔍 Monitoring Methods

### Method 1: Automatic Monitoring Script (Recommended)

```bash
# Run during or after cluster creation
bash scripts/monitor-compute-node-setup.sh p5en-48xlarge-cluster us-east-2
```

**Output**:
- CloudFormation stack status
- EC2 instance status
- Installation progress from CloudWatch logs
- Instructions to access the HeadNode

### Method 2: Real-time CloudWatch Logs Monitoring

```bash
# Stream real-time logs
aws logs tail /aws/parallelcluster/p5en-48xlarge-cluster \
  --region us-east-2 \
  --follow \
  --filter-pattern "Compute"

# Filter only installation steps
aws logs tail /aws/parallelcluster/p5en-48xlarge-cluster \
  --region us-east-2 \
  --follow \
  --filter-pattern "\"Installing\" OR \"✓\" OR \"Complete\""
```

### Method 3: Verify Specific Component Installation

```bash
CLUSTER_NAME="p5en-48xlarge-cluster"
REGION="us-east-2"

# Verify EFA installation
aws logs filter-log-events \
  --log-group-name "/aws/parallelcluster/${CLUSTER_NAME}" \
  --region ${REGION} \
  --filter-pattern "\"Installing EFA\" OR \"EFA installation complete\"" \
  --max-items 10

# Verify Docker installation
aws logs filter-log-events \
  --log-group-name "/aws/parallelcluster/${CLUSTER_NAME}" \
  --region ${REGION} \
  --filter-pattern "\"Installing Docker\" OR \"Docker installation complete\"" \
  --max-items 10

# Verify NCCL configuration
aws logs filter-log-events \
  --log-group-name "/aws/parallelcluster/${CLUSTER_NAME}" \
  --region ${REGION} \
  --filter-pattern "\"NCCL\" OR \"nccl\"" \
  --max-items 10
```

### Method 4: Check EC2 Instance Status

```bash
# List ComputeNode instances
aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${CLUSTER_NAME}" \
            "Name=tag:Name,Values=Compute" \
  --region ${REGION} \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,IP:PrivateIpAddress,LaunchTime:LaunchTime}' \
  --output table

# If instances are in the "shutting-down" state, a timeout has occurred
# If instances remain in the "running" state, the installation is in progress
```

### Method 5: Check Directly on the HeadNode

```bash
# SSH to the HeadNode
ssh headnode

# Check Slurm node status
sinfo -N -l

# Run the installation status check script on a ComputeNode
srun --nodes=1 bash /fsx/scripts/check-compute-setup.sh

# Check all ComputeNodes
srun --nodes=ALL bash /fsx/scripts/check-compute-setup.sh
```

## 📊 Log Messages by Installation Phase

### 1. Initialization Phase
```
=== Compute Node Setup Started ===
Cluster Name: p5en-48xlarge-cluster
Region: us-east-2
Checking FSx Lustre mount...
✓ FSx Lustre mounted at /fsx
```

### 2. Parallel Installation Phase
```
Installing EFA...
Installing Docker + NVIDIA Container Toolkit...
Installing CloudWatch Agent...
```

### 3. EFA Installation (Takes the longest)
```
GPU detected - installing with GPU support
Installed EFA packages:
✓ EFA installation complete
```

### 4. Docker Installation
```
✓ Docker + NVIDIA Container Toolkit installation complete
```

### 5. Pyxis Installation
```
Installing Pyxis (Slurm container plugin)...
✓ Pyxis installation complete
(or)
⚠️  Pyxis build failed (non-critical)
```

### 6. Monitoring Configuration
```
Configuring DCGM Exporter...
✓ DCGM Exporter configured (port 9400)
Installing Node Exporter...
✓ Node Exporter configured (port 9100)
```

### 7. NCCL Configuration (if applicable)
```
Checking for shared NCCL installation...
Found shared NCCL, configuring environment...
✓ Shared NCCL configured
(or)
⚠️  Shared NCCL not found in /fsx/nccl/
```

### 8. Completion
```
✓ Compute Node Setup Complete
Installed components:
  - EFA Driver + libfabric
  - Docker + NVIDIA Container Toolkit
  - Pyxis (Slurm container plugin)
  - CloudWatch Agent
  - DCGM Exporter (port 9400) - GPU metrics
  - Node Exporter (port 9100) - System metrics
```

## 🚨 Troubleshooting

### Timeout Occurred (Nodes are "shutting-down")

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name ${CLUSTER_NAME} \
  --region ${REGION} \
  --query 'StackEvents[?contains(ResourceStatusReason, `timeout`) || contains(ResourceStatusReason, `Timeout`)]'

# Check the last log entries (where it got stuck)
aws logs get-log-events \
  --log-group-name "/aws/parallelcluster/${CLUSTER_NAME}" \
  --log-stream-name "ip-10-1-XX-XX.i-XXXXX.cloud-init-output" \
  --region ${REGION} \
  --limit 100 \
  --start-from-head \
  --query 'events[-20:].message' \
  --output text
```

**Common Timeout Causes**:
1. EFA installation failure (network issue)
2. Docker installation failure
3. Pyxis build failure (missing Slurm headers) ← Already fixed
4. Timeouts set too short ← Check DevSettings.Timeouts

### Investigate Installation Errors

```bash
# Search for error messages
aws logs filter-log-events \
  --log-group-name "/aws/parallelcluster/${CLUSTER_NAME}" \
  --region ${REGION} \
  --filter-pattern "\"Error\" OR \"Failed\" OR \"❌\" OR \"fatal\"" \
  --max-items 50

# Search for warning messages
aws logs filter-log-events \
  --log-group-name "/aws/parallelcluster/${CLUSTER_NAME}" \
  --region ${REGION} \
  --filter-pattern "\"Warning\" OR \"⚠️\"" \
  --max-items 50
```

### Troubleshoot Failed Component Installation

```bash
# Can manually reinstall on the HeadNode
ssh headnode

# Connect to a specific ComputeNode
srun --nodes=1 --nodelist=compute-node-1 bash

# Manual installation (e.g., Docker)
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl start docker
```

## 📈 Verify Successful Installation

### Check All Components

```bash
# Run on the HeadNode
srun --nodes=ALL bash /fsx/scripts/check-compute-setup.sh
```

**Expected Output**:
```
========================================
ComputeNode Setup Status
========================================
Hostname: compute-node-1
Date: Wed Nov 20 07:30:00 UTC 2025
========================================

=== System Information ===
OS:                           ✓ Installed
  PRETTY_NAME="Ubuntu 22.04.3 LTS"
Kernel:                       ✓ Installed
  6.8.0-1039-aws

=== GPU & Drivers ===
NVIDIA Driver:                ✓ Installed
  570.172.08
CUDA:                         ✓ Installed
  release 12.3
GPU Count:                    ✓ Installed
  8

=== EFA ===
EFA Installer:                ✓ Installed
Libfabric:                    ✓ Installed
EFA Devices:                  ✓ Installed

=== Container Runtime ===
Docker:                       ✓ Installed
  Docker version 24.0.5
NVIDIA Container Toolkit:     ✓ Installed

=== Monitoring ===
DCGM Exporter:                ✓ Running
Node Exporter:                ✓ Running

=== NCCL ===
NCCL Profile Script:          ✓ Installed
NCCL Version:                 ✓ Installed
  v2.28.7-1

========================================
Setup Summary
========================================

Installation Progress: 9/9 components (100%)

✓ All components installed successfully!
```

### Test Individual Components

```bash
# Test GPU
srun --nodes=1 --gpus=1 nvidia-smi

# Test Docker
srun --nodes=1 docker run --rm hello-world

# Test NCCL
srun --nodes=2 --ntasks=16 --gpus-per-task=1 \
  /opt/nccl-tests/build/all_reduce_perf -b 8 -e 128M -f 2 -g 1

# Test EFA
srun --nodes=2 --ntasks=2 \
  /opt/amazon/efa/bin/fi_pingpong -p efa
```

## 🎯 Quick Checklist

After cluster creation, check the following in order:

1. ✅ **CloudFormation Stack Status**
   ```bash
   aws cloudformation describe-stacks --stack-name ${CLUSTER_NAME} --region ${REGION} --query 'Stacks[0].StackStatus'
   ```
   → `CREATE_COMPLETE` or `CREATE_IN_PROGRESS`

2. ✅ **ComputeNode Instance Status**
   ```bash
   aws ec2 describe-instances --filters "Name=tag:Name,Values=Compute" --query 'Reservations[*].Instances[*].State.Name'
   ```
   → `running` (if "shutting-down", a timeout has occurred)

3. ✅ **Check CloudWatch Logs**
   ```bash
   aws logs tail /aws/parallelcluster/${CLUSTER_NAME} --region ${REGION} --since 10m
   ```
   → Verify installation progress messages

4. ✅ **Check Slurm on the HeadNode**
   ```bash
   ssh headnode
   sinfo -N -l
   ```
   → Verify ComputeNode status

5. ✅ **Verify Installation Status**
   ```bash
   srun --nodes=1 bash /fsx/scripts/check-compute-setup.sh
   ```
   → Confirm 100% completion

## 📚 Related Documentation

- [TIMEOUT-CONFIGURATION.md](TIMEOUT-CONFIGURATION.md) - Timeout Configuration
- [config/headnode/README.md](config/headnode/README.md) - NCCL Installation
- [config/compute/setup-compute-node.sh](config/compute/setup-compute-node.sh) - Installation Script
- [TROUBLESHOOTING.md](guide/TROUBLESHOOTING.md) - Troubleshooting

## 💡 Tips

1. **Real-time Monitoring**: Start log monitoring as soon as the cluster creation begins
2. **Generous Timeouts**: Set DevSettings.Timeouts generously (recommend 40 minutes)
3. **Ignore Errors**: Failures in some optional components (e.g., Pyxis) are normal
4. **Automatic Retries**: ParallelCluster will automatically restart failed nodes
5. **Manual Verification**: If in doubt, directly check on the HeadNode
