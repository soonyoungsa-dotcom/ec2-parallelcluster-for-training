#!/bin/bash
# EFA Installer upgrade script
# Executed from ParallelCluster CustomActions

set -exo pipefail

EFA_VERSION=${1:-latest}

echo "=== EFA Installer ${EFA_VERSION} Installation Started ==="

# Check current EFA version
if [ -f /opt/amazon/efa_installed_packages ]; then
    echo "Current installed EFA packages:"
    cat /opt/amazon/efa_installed_packages
fi

# Download and install EFA Installer
cd /tmp
curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_VERSION}.tar.gz
tar -xf aws-efa-installer-${EFA_VERSION}.tar.gz
cd aws-efa-installer

# EFA installation options:
# -y: Auto yes (no prompts)
# -g: GPU support (NCCL, NVIDIA GPU Direct RDMA)
# -k: Skip kernel module installation (if already installed)

# Check for GPU instance
if lspci | grep -i nvidia > /dev/null 2>&1; then
    echo "GPU detected - installing with GPU support"
    sudo ./efa_installer.sh -y -g
else
    echo "No GPU - installing basic EFA"
    sudo ./efa_installer.sh -y
fi

# Verify installation
echo "=== EFA Installation Complete ==="
echo "Installed packages:"
cat /opt/amazon/efa_installed_packages

# Check Libfabric version
echo "Libfabric version:"
/opt/amazon/efa/bin/fi_info --version

# Check EFA devices (only exists on ComputeNode)
echo "EFA devices:"
ls -la /dev/infiniband/ 2>/dev/null || echo "No EFA devices (normal for HeadNode)"

# Cleanup
cd /tmp
rm -rf aws-efa-installer-*.tar.gz aws-efa-installer

echo "=== EFA Installer ${EFA_VERSION} Installation Complete ==="
