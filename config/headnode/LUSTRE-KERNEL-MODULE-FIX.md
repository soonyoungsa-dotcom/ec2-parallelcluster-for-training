# Guide to Resolve Lustre Kernel Module Version Mismatch

## Root Cause

### Underlying Cause
1. **Ubuntu Automatic Security Updates**
   - `unattended-upgrades` package automatically updates the kernel in the background
   - Can occur a few hours to days after cluster creation

2. **Lustre Module Kernel Dependence**
   - Lustre client modules must match the exact kernel version
   - Modules for kernel `6.8.0-1039` won't work with `6.8.0-1042`

3. **Failure Scenario**
   ```
   Cluster creation (kernel 6.8.0-1039)
   → Install Lustre modules for 6.8.0-1039
   → Automatic update installs kernel 6.8.0-1042
   → Reboot
   → Boot into kernel 6.8.0-1042
   → Lustre modules 6.8.0-1039 are incompatible
   → /fsx mount fails
   ```

## Resolution Methods

### Method 1: Immediate Manual Fix (Urgent)

```bash
# Run on the HeadNode
sudo su

# Check current kernel
uname -r

# Install matching Lustre modules
apt-get update
apt-get install -y lustre-client-modules-$(uname -r)

# Load Lustre modules
modprobe lustre

# Mount /fsx
systemctl restart fsx.mount

# Verify
df -h | grep fsx
```

### Method 2: Automatic Fix Script (Recommended)

#### A. Integrate into setup-headnode.sh

Add the following at the beginning of `setup-headnode.sh`:

```bash
#!/bin/bash

# Fix Lustre module before anything else
echo "=== Checking Lustre kernel module ==="
KERNEL_VERSION=$(uname -r)

if [ ! -d "/lib/modules/${KERNEL_VERSION}/updates/kernel/fs/lustre" ]; then
    echo "Installing Lustre module for ${KERNEL_VERSION}..."
    apt-get update -qq
    apt-get install -y lustre-client-modules-${KERNEL_VERSION}
fi

if ! lsmod | grep -q lustre; then
    modprobe lustre
fi

if ! mountpoint -q /fsx; then
    systemctl restart fsx.mount
    sleep 2
fi

echo "✓ Lustre ready"
```

#### B. Use a Standalone Script

```bash
# Download from S3
aws s3 cp s3://pcluster-setup-269550163595/config/headnode/fix-lustre-module.sh /tmp/
sudo bash /tmp/fix-lustre-module.sh
```

#### C. Add to CustomActions

Add the following to `cluster-config.yaml.template`:

```yaml
HeadNode:
  CustomActions:
    OnNodeStart:  # Run on every boot
      Sequence:
        - Script: 's3://pcluster-setup-269550163595/config/headnode/fix-lustre-module.sh'
    OnNodeConfigured:
      Sequence:
        - Script: 's3://pcluster-setup-269550163595/config/headnode/setup-headnode.sh'
```

### Method 3: Prevent Kernel Auto-Updates (Preventive)

#### A. Apply During Cluster Creation

Add the following to `environment-variables-bailey.sh`:

```bash
# Add kernel update prevention script to HeadNode CustomActions
HEADNODE_CUSTOM_ACTIONS="
- Script: 's3://${S3_BUCKET}/config/headnode/disable-kernel-auto-update.sh'
- Script: 's3://${S3_BUCKET}/config/headnode/setup-headnode.sh'
  Args:
    - ${CLUSTER_NAME}
    - ${AWS_REGION}
"
```

#### B. Apply to Existing Cluster

```bash
# Run on the HeadNode
sudo bash /fsx/config/headnode/disable-kernel-auto-update.sh
```

This script:
- ✅ Adds kernel packages to the auto-update blacklist
- ✅ Holds the current kernel version
- ✅ Fixes Lustre modules to the current kernel
- ✅ Creates a boot-time Lustre module check service

### Method 4: Systemd Service for Automation (Highest Stability)

```bash
# Create /etc/systemd/system/lustre-module-check.service
cat > /etc/systemd/system/lustre-module-check.service << 'EOF'
[Unit]
Description=Check and fix Lustre kernel module on boot
After=network.target
Before=fsx.mount

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-lustre-module.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Copy the script
sudo cp /fsx/config/headnode/fix-lustre-module.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/fix-lustre-module.sh

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable lustre-module-check.service
```

## Recommended Workflows

### New Cluster Creation

1. **Preventive Measures (Recommended)**
   ```bash
   # Modify environment-variables-bailey.sh
   # Add disable-kernel-auto-update.sh to HeadNode CustomActions
   
   # Create the cluster
   pcluster create-cluster --cluster-name my-cluster \
     --cluster-configuration cluster-config.yaml
   ```

2. **Post-Creation Verification**
   ```bash
   # SSH to the HeadNode
   ssh headnode
   
   # Check Lustre status
   /fsx/scripts/check-lustre.sh
   ```

### Existing Cluster Update

1. **Immediate Fix**
   ```bash
   sudo bash /fsx/config/headnode/fix-lustre-module.sh
   ```

2. **Permanent Prevention**
   ```bash
   sudo bash /fsx/config/headnode/disable-kernel-auto-update.sh
   ```

3. **Verification**
   ```bash
   /fsx/scripts/check-lustre.sh
   apt-mark showhold | grep linux
   ```

## Troubleshooting

### Symptom: /fsx Mount Failure

```bash
# Check the error
systemctl status fsx.mount
journalctl -u fsx.mount -n 50

# Common error messages:
# "mount.lustre: mount fs-xxx at /fsx failed: No such device"
# "Are the lustre modules loaded?"
```

**Resolution:**
```bash
# 1. Check the kernel version
uname -r

# 2. Verify installed Lustre modules
dpkg -l | grep lustre-client-modules

# 3. Install the matching module
sudo apt-get install -y lustre-client-modules-$(uname -r)

# 4. Load the module
sudo modprobe lustre

# 5. Retry the mount
sudo systemctl restart fsx.mount
```

### Symptom: Module Installation Failure

```bash
# Error: "Unable to locate package lustre-client-modules-6.8.0-1042-aws"
```

**Resolution:**
```bash
# 1. Check the FSx Lustre repo
cat /etc/apt/sources.list.d/fsxlustreclientrepo.list

# 2. Update the repo
sudo apt-get update

# 3. Check available modules
apt-cache search lustre-client-modules | grep $(uname -r | cut -d- -f1-2)

# 4. Re-add the repo (if needed)
wget -O - https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-ubuntu-public-key.asc | sudo apt-key add -
sudo bash -c 'echo "deb https://fsx-lustre-client-repo.s3.amazonaws.com/ubuntu jammy main" > /etc/apt/sources.list.d/fsxlustreclientrepo.list'
sudo apt-get update
```

## File Locations

Created scripts:

```
/fsx/config/headnode/
├── fix-lustre-module.sh              # Automatic Lustre module fix
├── disable-kernel-auto-update.sh     # Prevent kernel auto-updates
└── download-ngc-containers.sh        # Includes Lustre check

/fsx/scripts/
└── check-lustre.sh                   # Lustre health check

/etc/systemd/system/
└── lustre-module-check.service       # Automatic boot-time check service
```

## Monitoring

### Periodic Checks

```bash
# Add a daily Cron check
echo "0 2 * * * **** /fsx/scripts/check-lustre.sh >> /var/log/lustre-check.log 2>&1" | sudo tee -a /etc/crontab
```

### CloudWatch Alarms

```bash
# Alarm on Lustre mount failure
aws cloudwatch put-metric-alarm \
  --alarm-name lustre-mount-failed \
  --alarm-description "Lustre filesystem not mounted" \
  --metric-name LustreAvailable \
  --namespace ParallelCluster \
  --statistic Average \
  --period 300 \
  --threshold 1 \
  --comparison-operator LessThanThreshold
```

## References

- [AWS FSx for Lustre Client](https://docs.aws.amazon.com/fsx/latest/LustreGuide/install-lustre-client.html)
- [Ubuntu Unattended Upgrades](https://help.ubuntu.com/community/AutomaticSecurityUpdates)
- [ParallelCluster CustomActions](https://docs.aws.amazon.com/parallelcluster/latest/ug/custom-bootstrap-actions-v3.html)
