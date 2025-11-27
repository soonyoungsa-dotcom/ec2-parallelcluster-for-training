# ParallelCluster Guide Documentation

This directory contains detailed guides for configuring and operating AWS ParallelCluster.

## 📚 List of Documents

### Installation and Configuration

- **[INSTANCE-TYPE-CONFIGURATION.md](INSTANCE-TYPE-CONFIGURATION.md) ⭐ NEW**
  - Guide for instance type-specific configuration
  - Settings for GPU+EFA, GPU-Only, and Non-GPU instances
  - Selective installation of EFA, DCGM, and Node Exporter
  - Recommended settings for each instance type

- **[TIMEOUT-CONFIGURATION.md](TIMEOUT-CONFIGURATION.md)**
  - ComputeNode bootstrap timeout configuration
  - Troubleshooting timeout issues
  - Recommended timeout values and rationale

- **[TESTING-MINIMAL-CLUSTER.md](TESTING-MINIMAL-CLUSTER.md)**
  - Guide for testing a minimal cluster configuration
  - Testing with CustomActions disabled
  - Identifying root causes of issues

### Monitoring and Debugging

- **[MONITORING-SETUP-PROGRESS.md](MONITORING-SETUP-PROGRESS.md)**
  - Monitoring ComputeNode installation progress
  - Checking CloudWatch Logs
  - Log messages for each installation step
  - Troubleshooting checklist

### Performance and Optimization

- **[NCCL-INSTALLATION-TIMING.md](NCCL-INSTALLATION-TIMING.md)**
  - Analysis of NCCL installation time
  - Time breakdown by component
  - Comparison of NGC container vs. manual installation

## 🔗 Related Documents

### Main Documentation
- [../README.md](../README.md) - Project overview and Quick Start

### Configuration Files
- [../cluster-config.yaml.template](../cluster-config.yaml.template) - Cluster configuration template
- [../environment-variables.sh](../environment-variables.sh) - Environment variables setup

### Scripts
- [../scripts/monitor-compute-node-setup.sh](../scripts/monitor-compute-node-setup.sh) - Installation monitoring script
- [../scripts/check-compute-setup.sh](../scripts/check-compute-setup.sh) - Installation status check script

### Configuration Directories
- [../config/headnode/README.md](../config/headnode/README.md) - HeadNode configuration guide
- [../config/nccl/README.md](../config/nccl/README.md) - NCCL installation and testing

## 📖 How to Use the Documentation

### Before Cluster Creation
1. [INSTANCE-TYPE-CONFIGURATION.md](INSTANCE-TYPE-CONFIGURATION.md) - Instance type-specific configuration ⭐
2. [TIMEOUT-CONFIGURATION.md](TIMEOUT-CONFIGURATION.md) - Review timeout configuration
3. [TESTING-MINIMAL-CLUSTER.md](TESTING-MINIMAL-CLUSTER.md) - Develop a testing strategy

### During Cluster Creation
1. [MONITORING-SETUP-PROGRESS.md](MONITORING-SETUP-PROGRESS.md) - Real-time monitoring

### When Issues Occur
1. [MONITORING-SETUP-PROGRESS.md](MONITORING-SETUP-PROGRESS.md) - Check logs
2. [TIMEOUT-CONFIGURATION.md](TIMEOUT-CONFIGURATION.md) - Troubleshoot timeout issues
3. [TESTING-MINIMAL-CLUSTER.md](TESTING-MINIMAL-CLUSTER.md) - Test the minimal configuration

### When Installing NCCL
1. [NCCL-INSTALLATION-TIMING.md](NCCL-INSTALLATION-TIMING.md) - Estimate installation time
2. [../config/nccl/README.md](../config/nccl/README.md) - Installation methods

## 💡 Quick References

### Timeout Configuration
```yaml
DevSettings:
  Timeouts:
    HeadNodeBootstrapTimeout: 3600      # 60 minutes
    ComputeNodeBootstrapTimeout: 2400   # 40 minutes
```

### Monitoring Installation
```bash
bash scripts/monitor-compute-node-setup.sh <cluster-name> <region>
```

### Testing Minimal Configuration
```bash
# environment-variables.sh
export ENABLE_COMPUTE_SETUP="false"
```

### Checking Installation Status
```bash
srun --nodes=1 bash /fsx/scripts/check-compute-setup.sh
```
