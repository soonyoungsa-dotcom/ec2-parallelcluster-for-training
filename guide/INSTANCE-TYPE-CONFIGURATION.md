# Instance Type-Specific Configuration Guide

This guide explains how to selectively configure the required components when using different instance types in ParallelCluster.

## 📋 Table of Contents

- [Instance Type Characteristics](#Instance-Type-Characteristics)
- [Configuration Method](#Configuration-Method)
- [Recommended Instance Type-Specific Settings](#Recommended-Instance-Type-Specific-Settings)
- [Component Descriptions](#Component-Descriptions)
- [Application Method](#Application-Method)

## 🎯 Instance Type Characteristics

### 1. GPU + EFA Instances (Multi-Node Training)

**Instance Types**: p5en.48xlarge, p4d.24xlarge, p5.48xlarge

**Characteristics:**
- ✅ GPU support (H100, A100)
- ✅ EFA (Elastic Fabric Adapter) support - up to 3.2Tbps
- ✅ Optimized for multi-node distributed training
- ✅ High-speed GPU-to-GPU communication with NCCL over EFA

**Use Cases:**
- Large language model (LLM) training
- Multi-node distributed training
- High-performance GPU clusters

### 2. GPU-Only Instances (Single-Node Training)

**Instance Types**: g5.xlarge, g5.12xlarge, g4dn.xlarge

**Characteristics:**
- ✅ GPU support (A10G, T4)
- ❌ No EFA support
- ✅ Suitable for single-node training
- ✅ Cost-effective

**Use Cases:**
- Single-node model training
- Inference workloads
- Development and testing

### 3. Non-GPU Instances (General Computing)

**Instance Types**: c5.xlarge, m5.large, r5.xlarge

**Characteristics:**
- ❌ No GPU
- ❌ No EFA support
- ✅ CPU-based workloads
- ✅ Cost-effective

**Use Cases:**
- Data preprocessing
- CPU-based training
- General computing tasks

## ⚙️ Configuration Method

### environment-variables-bailey.sh Configuration

```bash
# ComputeNode: Setup configuration
export COMPUTE_SETUP_TYPE="gpu"         # "gpu", "cpu", or "" (disabled)
```

### Configuration Options Explained

| Value | Description | Installed Items | Installation Time |
|----|------|-----------|-----------|
| `"gpu"` | For GPU instances (default) | Docker + Pyxis + EFA + DCGM + Node Exporter | ~15-20 minutes |
| `"cpu"` | For CPU instances | Docker + Pyxis | ~5-10 minutes |
| `""` | Disabled installation (for testing) | None (ParallelCluster default only) | ~1-2 minutes |

## 🔧 Recommended Instance Type-Specific Settings

### 1. GPU Instances (p5, p4d, g5, g4dn)

```bash
# environment-variables-bailey.sh
export COMPUTE_SETUP_TYPE="gpu"
```

**Installed Components:**
- ✅ EFA Driver + libfabric (high-speed networking, p5/p4d only)
- ✅ Docker + NVIDIA Container Toolkit
- ✅ Pyxis (Slurm container plugin)
- ✅ CloudWatch Agent (logs and metrics)
- ✅ DCGM Exporter (port 9400) - GPU metrics
- ✅ Node Exporter (port 9100) - system metrics

**Installation Time**: ~15-20 minutes

**Auto-Detection:**
- EFA is installed only on supported instances
- DCGM Exporter is automatically skipped if no GPU is present

### 2. CPU Instances (c5, m5, r5)

```bash
# environment-variables-bailey.sh
export COMPUTE_SETUP_TYPE="cpu"
```

**Installed Components:**
- ✅ Docker
- ✅ Pyxis (Slurm container plugin)
- ✅ CloudWatch Agent (logs and metrics)

**Installation Time**: ~5-10 minutes

### 3. Minimal Setup (Testing/Development)

```bash
# environment-variables-bailey.sh
export COMPUTE_SETUP_TYPE=""            # Empty string = Disabled
```

**Installed Components:**
- ✅ ParallelCluster default setup only

**Installation Time**: ~1-2 minutes

## 📦 Component Descriptions

### EFA (Elastic Fabric Adapter)

**Purpose**: High-speed network communication (multi-node training)

**When needed:**
- Multi-node GPU training
- NCCL All-Reduce communication
- p5, p4d instances

**When not needed:**
- Single-node training
- Instances without EFA support (g5, c5, m5, etc.)

**Performance:**
- p5en.48xlarge: Up to 3.2Tbps
- p4d.24xlarge: Up to 400Gbps

### DCGM Exporter

**Purpose**: Collect GPU metrics (for Prometheus)

**Collected Metrics:**
- GPU utilization
- GPU memory usage
- GPU temperature
- GPU power consumption

**When needed:**
- Monitoring GPU instances
- Tracking GPU performance
- Prometheus dashboards

**When not needed:**
- Non-GPU instances
- Using CloudWatch only

### Node Exporter

**Purpose**: Collect system metrics (for Prometheus)

**Collected Metrics:**
- CPU utilization
- Memory usage
- Disk I/O
- Network traffic

**When needed:**
- Prometheus monitoring
- Tracking system performance
- Custom dashboards

**When not needed:**
- Using CloudWatch only
- Minimizing monitoring

## 🚀 Application Method

### Step 1: Set Environment Variables

```bash
cd parallelcluster-for-llm
vim environment-variables-bailey.sh

# Modify the settings based on the instance type
export COMPUTE_SETUP_TYPE="cpu"         # e.g., CPU instances
# or
export COMPUTE_SETUP_TYPE="gpu"         # e.g., GPU instances
# or
export COMPUTE_SETUP_TYPE=""            # e.g., Minimal setup (testing)
```

### Step 2: Create the Configuration

```bash
source environment-variables-bailey.sh
envsubst < cluster-config.yaml.template > cluster-config.yaml
```

### Step 3: Upload to S3

```bash
aws s3 sync config/ s3://${S3_BUCKET}/config/ --region ${AWS_REGION}
```

### Step 4: Create/Update the Cluster

```bash
# Create a new cluster
pcluster create-cluster \
    --cluster-name ${CLUSTER_NAME} \
    --cluster-configuration cluster-config.yaml

# Update an existing cluster
pcluster update-cluster \
    --cluster-name ${CLUSTER_NAME} \
    --cluster-configuration cluster-config.yaml
```

## 🔍 Verification

### Verify the Configuration

```bash
# Check the environment variables
source environment-variables-bailey.sh
echo "Compute Setup Type: ${COMPUTE_SETUP_TYPE}"
```

### Verify After Cluster Creation

```bash
# SSH into a Compute Node
ssh compute-node-1

# Check EFA (if enabled)
ls -la /dev/infiniband/
/opt/amazon/efa/bin/fi_info --version

# Check DCGM Exporter (if enabled)
sudo systemctl status dcgm-exporter
curl http://localhost:9400/metrics

# Check Node Exporter (if enabled)
sudo systemctl status node-exporter
curl http://localhost:9100/metrics

# Check CloudWatch Agent (always enabled)
sudo systemctl status amazon-cloudwatch-agent
```

## 📊 Comparison Table

| Item | GPU Mode | CPU Mode | Minimal Setup |
|------|----------|----------|---------------|
| **Configuration Value** | `"gpu"` | `"cpu"` | `""` |
| **Instance Examples** | p5, p4d, g5, g4dn | c5, m5, r5 | All types |
| **Docker** | ✅ + NVIDIA Toolkit | ✅ | ❌ |
| **Pyxis** | ✅ | ✅ | ❌ |
| **EFA** | ✅ (auto-detected) | ❌ | ❌ |
| **DCGM Exporter** | ✅ (if GPU present) | ❌ | ❌ |
| **Node Exporter** | ✅ | ❌ | ❌ |
| **CloudWatch Agent** | ✅ | ✅ | ✅ (default) |
| **GPU Metrics** | ✅ | ❌ | ❌ |
| **System Metrics (Prometheus)** | ✅ | ❌ | ❌ |
| **System Metrics (CloudWatch)** | ✅ | ✅ | ✅ |
| **Installation Time** | ~15-20 minutes | ~5-10 minutes | ~1-2 minutes |
| **Use Cases** | GPU training/inference | CPU workloads | Testing/development |

## 💡 Recommendations

### Production Environment

**GPU Instances (p5, p4d, g5, g4dn):**
```bash
export COMPUTE_SETUP_TYPE="gpu"
```
- Install all GPU monitoring and optimization tools
- EFA is automatically installed on supported instances

**CPU Instances (c5, m5, r5):**
```bash
export COMPUTE_SETUP_TYPE="cpu"
```
- Install only Docker + Pyxis
- Faster boot time

### Development/Testing Environment

**For quick testing:**
```bash
export COMPUTE_SETUP_TYPE=""
```
- Minimal setup for fast cluster creation
- Test basic functionality only

**For actual workload testing:**
```bash
export COMPUTE_SETUP_TYPE="gpu"  # or "cpu"
```
- Test in an environment identical to production

## 🛠️ Troubleshooting

### EFA Installation Failure

```bash
# Check EFA devices
ls -la /dev/infiniband/

# Verify supported instance types
# Only p5, p4d, p4de support EFA
```

### DCGM Exporter Startup Failure

```bash
# Check GPUs
lspci | grep -i nvidia

# Check Docker
sudo systemctl status docker

# DCGM Exporter logs
sudo journalctl -u dcgm-exporter -n 50
```

### Node Exporter Startup Failure

```bash
# Check Node Exporter binary
ls -l /usr/local/bin/node_exporter

# Check logs
sudo journalctl -u node-exporter -n 50
```

## 📚 Related Documentation

- [CloudWatch Monitoring Guide](../config/cloudwatch/README.md)
- [Cluster Configuration Guide](../README.md)
- [Timeout Configuration](TIMEOUT-CONFIGURATION.md)
- [Testing Minimal Cluster](TESTING-MINIMAL-CLUSTER.md)

## 🔗 AWS Documentation

- [EFA-Enabled Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html)
- [GPU Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/accelerated-computing-instances.html)
- [ParallelCluster Instance Types](https://docs.aws.amazon.com/parallelcluster/latest/ug/instance-types.html)
