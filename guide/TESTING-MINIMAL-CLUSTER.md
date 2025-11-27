# Guide for Testing a Minimal Cluster Configuration

## Purpose

This guide tests the basic cluster creation by disabling the ComputeNode CustomActions.

## Why is this Necessary?

If ComputeNodes fail even with sufficient timeouts set:
1. There may be an issue with the CustomActions script itself.
2. The ParallelCluster default configuration may have a problem.
3. There could be an infrastructure issue (networking, permissions, etc.).

Testing the minimal configuration can help you **identify the root cause** of the problem.

## Current State

### ✅ Disabled (Test Mode)

```bash
# environment-variables-bailey.sh
export ENABLE_COMPUTE_SETUP="false"  # Disable CustomActions
```

```yaml
# cluster-config.yaml
# CustomActions temporarily disabled for testing
# (Commented out)
```

### What Gets Installed

**ParallelCluster default installation only**:
- ✅ Ubuntu 22.04 OS
- ✅ Slurm worker configuration
- ✅ FSx Lustre mount (/fsx)
- ✅ HeadNode NFS mount (/home)
- ✅ Basic networking

**Not Installed**:
- ❌ EFA Driver
- ❌ Docker + NVIDIA Container Toolkit
- ❌ Pyxis
- ❌ CloudWatch Agent
- ❌ DCGM Exporter
- ❌ Node Exporter
- ❌ NCCL setup

## Test Procedure

### 1. Verify Environment Variables

```bash
# Check environment-variables-bailey.sh
grep "ENABLE_COMPUTE_SETUP" environment-variables-bailey.sh

# Output: export ENABLE_COMPUTE_SETUP="false"
```

### 2. Regenerate Cluster Configuration

```bash
# Load the environment variables
source environment-variables-bailey.sh

# Generate the configuration file
envsubst < cluster-config.yaml.template > cluster-config.yaml

# Verify that CustomActions are commented out
grep -A 5 "CustomActions" cluster-config.yaml
```

### 3. Create the Cluster

```bash
# Delete the existing cluster (if any)
pcluster delete-cluster --cluster-name p5en-48xlarge-cluster --region us-east-2

# Wait for the deletion to complete
pcluster describe-cluster --cluster-name p5en-48xlarge-cluster --region us-east-2

# Create a new cluster
pcluster create-cluster \
  --cluster-name p5en-48xlarge-cluster \
  --cluster-configuration cluster-config.yaml \
  --region us-east-2
```

### 4. Monitor the Creation

```bash
# Real-time monitoring
bash scripts/monitor-compute-node-setup.sh p5en-48xlarge-cluster us-east-2

# Or check CloudWatch logs
aws logs tail /aws/parallelcluster/p5en-48xlarge-cluster \
  --region us-east-2 --follow

# Check instance states
watch -n 10 'aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=Compute" \
  --query "Reservations[*].Instances[*].{State:State.Name,LaunchTime:LaunchTime}" \
  --output table'
```

### 5. Verify Success

**Expected Time**: 5-10 minutes (very fast without CustomActions)

**Successful Indicators**:
```bash
# 1. CloudFormation stack completed
aws cloudformation describe-stacks \
  --stack-name p5en-48xlarge-cluster \
  --region us-east-2 \
  --query 'Stacks[0].StackStatus'
# Output: CREATE_COMPLETE

# 2. ComputeNodes are running
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=Compute" \
  --query 'Reservations[*].Instances[*].State.Name'
# Output: running (not shutting-down!)

# 3. Slurm nodes registered
ssh headnode
sinfo -N -l
# Output: compute-node-1  idle  (or allocated)
```

### 6. Test Basic Functionality

```bash
# Access the HeadNode
ssh headnode

# Verify Slurm operation
sinfo
squeue

# Run a simple command on ComputeNode
srun --nodes=1 hostname
srun --nodes=1 uptime
srun --nodes=1 df -h /fsx

# Check GPU (NVIDIA driver is installed by default)
srun --nodes=1 nvidia-smi

# Run a simple calculation test
srun --nodes=2 --ntasks=2 hostname
```

## Analyze Test Results

### Scenario A: Minimal Configuration Succeeds ✅

**Meaning**: ParallelCluster default configuration is fine, the issue is with CustomActions.

**Next Steps**:
1. Review the CustomActions scripts.
2. Test manual installation of individual components.
3. Identify and fix the problematic component.

```bash
# Test manual component installation
ssh headnode
srun --nodes=1 bash << 'EOF'
  # Test EFA installation
  cd /tmp
  curl -O https://efa-installer.amazonaws.com/aws-efa-installer-latest.tar.gz
  tar -xf aws-efa-installer-latest.tar.gz
  cd aws-efa-installer
  sudo ./efa_installer.sh -y
EOF
```

### Scenario B: Minimal Configuration Also Fails ❌

**Meaning**: There is an issue with the ParallelCluster default configuration or the infrastructure.

**Things to Check**:
1. **Networking**: Private Subnet, NAT Gateway, Routing
2. **Permissions**: IAM role, policies
3. **Resources**: Capacity Block reservation status
4. **Region**: Resource availability

```bash
# Check networking
aws ec2 describe-subnets --subnet-ids subnet-XXXXX --region us-east-2
aws ec2 describe-route-tables --region us-east-2

# Check IAM role
aws iam get-role --role-name parallelcluster-* --region us-east-2

# Check Capacity Block
aws ec2 describe-capacity-reservations \
  --capacity-reservation-ids cr-XXXXX \
  --region us-east-2
```

## Re-enable CustomActions

After the test, re-enable the CustomActions:

### 1. Modify Environment Variables

```bash
# environment-variables-bailey.sh
export ENABLE_COMPUTE_SETUP="true"  # Re-enable
```

### 2. Regenerate Configuration

```bash
source environment-variables-bailey.sh
envsubst < cluster-config.yaml.template > cluster-config.yaml

# Verify that CustomActions are enabled
grep -A 10 "CustomActions" cluster-config.yaml
```

### 3. Recreate the Cluster

```bash
pcluster delete-cluster --cluster-name p5en-48xlarge-cluster --region us-east-2
pcluster create-cluster \
  --cluster-name p5en-48xlarge-cluster \
  --cluster-configuration cluster-config.yaml \
  --region us-east-2
```

## Gradual Enablement Strategy

To accurately identify the problem, you can enable the components one by one:

### Step 1: Install EFA Only

```bash
# Modify setup-compute-node.sh
# Comment out Docker, Pyxis, DCGM, etc.
# Keep only the EFA part
```

### Step 2: EFA + Docker

```bash
# Uncomment Docker
# Keep the rest commented
```

### Step 3: Full Enablement

```bash
# Enable all components
```

## Log Analysis

### Minimal Configuration Logs (Successful)

```
cloud-init[1234]: Cloud-init v. 23.1.2 running
...
[ParallelCluster] Configuring Slurm compute node
[ParallelCluster] Mounting shared filesystems
[ParallelCluster] FSx Lustre mounted at /fsx
[ParallelCluster] Node configuration complete
```

### CustomActions Enabled Logs (Successful)

```
=== Compute Node Setup Started ===
Cluster Name: p5en-48xlarge-cluster
...
Installing EFA...
✓ EFA installation complete
Installing Docker...
✓ Docker installation complete
...
✓ Compute Node Setup Complete
```

## Troubleshooting Tips

1. **Timeout vs. Script Error**
   - Timeout: Logs cut off in the middle
   - Script Error: Error message and then termination

2. **Networking Issues**
   - `curl` or `wget` failures
   - DNS resolution failures
   - Package download failures

3. **Permissions Issues**
   - S3 access denied
   - Insufficient IAM policies
   - Lack of resource creation permissions

## Summary

**Current State**: CustomActions disabled (Test Mode)

**Test Purpose**: Verify successful basic cluster creation

**Next Steps**:
- ✅ Success → CustomActions script issue, test individual components
- ❌ Failure → Infrastructure/configuration issue, check networking/permissions

**Re-enable**: Set `ENABLE_COMPUTE_SETUP="true"` and recreate the cluster
