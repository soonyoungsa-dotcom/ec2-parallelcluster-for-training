#!/bin/bash
# Compute Node Setup Script
# Everything needed for GPU training: EFA, Docker, CloudWatch, DCGM
# Note: NCCL is installed on FSx Lustre shared storage, not on compute nodes

# Don't exit on error - continue even if individual components fail
set +e

CLUSTER_NAME="${1:-my-cluster}"
REGION="${2:-us-east-1}"
S3_BUCKET="${3}"
MONITORING_TYPE="${4:-unknown}"  # Monitoring type (for informational purposes)
SETUP_TYPE="${5:-gpu}"  # Setup type: "gpu" or "cpu"

echo "=== Compute Node Setup Started ==="
echo "Cluster Name: ${CLUSTER_NAME}"
echo "Region: ${REGION}"
echo "Monitoring Type: ${MONITORING_TYPE}"
echo "Setup Type: ${SETUP_TYPE}"
echo ""

# Determine what to install based on setup type
if [ "$SETUP_TYPE" = "gpu" ]; then
    ENABLE_EFA_INSTALLER="true"
    ENABLE_DCGM_EXPORTER="true"
    ENABLE_NODE_EXPORTER="true"
    echo "GPU mode: Installing full GPU stack"
    echo "  - EFA Driver + libfabric"
    echo "  - Docker + NVIDIA Container Toolkit"
    echo "  - Pyxis (Slurm container plugin)"
    echo "  - DCGM Exporter (GPU metrics)"
    echo "  - Node Exporter (system metrics)"
    echo "  - CloudWatch Agent"
elif [ "$SETUP_TYPE" = "cpu" ]; then
    ENABLE_EFA_INSTALLER="false"
    ENABLE_DCGM_EXPORTER="false"
    ENABLE_NODE_EXPORTER="false"
    echo "CPU mode: Installing minimal stack"
    echo "  - Docker"
    echo "  - Pyxis (Slurm container plugin)"
    echo "  - CloudWatch Agent"
else
    echo "⚠️  Unknown setup type: ${SETUP_TYPE}"
    echo "   Defaulting to GPU mode"
    ENABLE_EFA_INSTALLER="true"
    ENABLE_DCGM_EXPORTER="true"
    ENABLE_NODE_EXPORTER="true"
fi
echo ""

# Verify FSx Lustre is mounted
echo ""
echo "Checking FSx Lustre mount..."
if mountpoint -q /fsx; then
    echo "✓ FSx Lustre mounted at /fsx"
    df -h /fsx | tail -1
else
    echo "⚠️  Warning: /fsx is not mounted"
    echo "   NCCL shared installation will not be available"
    echo "   Continuing with local setup only..."
fi
echo ""

# Start parallel installation (each in subshell with error handling)
# EFA Installer - Optional for high-speed networking
if [ "${ENABLE_EFA_INSTALLER}" = "true" ]; then
    {
        set +e  # Don't exit on error
        echo "Installing EFA..."
        
        # Check current EFA version if exists
        if [ -f /opt/amazon/efa_installed_packages ]; then
            echo "Current EFA packages:"
            cat /opt/amazon/efa_installed_packages
        fi
        
        # Download and extract EFA installer
        cd /tmp
        EFA_VERSION="latest"
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
            ./efa_installer.sh -y -g
        else
            echo "No GPU - installing basic EFA"
            ./efa_installer.sh -y
        fi
        
        # Verify installation
        echo "Installed EFA packages:"
        cat /opt/amazon/efa_installed_packages
        
        echo "Libfabric version:"
        /opt/amazon/efa/bin/fi_info --version
        
        echo "EFA devices:"
        ls -la /dev/infiniband/ 2>/dev/null || echo "No EFA devices (normal for non-EFA instances)"
        
        # Cleanup
        cd /tmp
        rm -rf aws-efa-installer-*.tar.gz aws-efa-installer
        
        echo "✓ EFA installation complete"
    } || echo "⚠️  EFA installation failed (non-critical)" &
else
    echo "EFA installation disabled (ENABLE_EFA_INSTALLER=false)"
    echo "Note: EFA is only needed for high-speed networking (p4d, p5, p5en instances)"
fi

{
    set +e  # Don't exit on error
    echo "Installing Docker + NVIDIA Container Toolkit..."
    apt-get install -y docker.io
    
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update
    apt-get install -y nvidia-container-toolkit
    
    systemctl enable docker
    systemctl start docker
    systemctl restart docker
    echo "✓ Docker + NVIDIA Container Toolkit installation complete"
} || echo "⚠️  Docker installation failed (non-critical)" &

{
    set +e  # Don't exit on error
    echo "Installing CloudWatch Agent..."
    
    if [ -n "${S3_BUCKET}" ]; then
        # Download and run installation script
        aws s3 cp "s3://${S3_BUCKET}/config/cloudwatch/install-cloudwatch-agent.sh" /tmp/ --region ${REGION}
        if [ -f "/tmp/install-cloudwatch-agent.sh" ]; then
            chmod +x /tmp/install-cloudwatch-agent.sh
            bash /tmp/install-cloudwatch-agent.sh "${CLUSTER_NAME}" "${REGION}" "${S3_BUCKET}"
        else
            echo "⚠️  CloudWatch Agent installation script not found"
        fi
    else
        echo "⚠️  Warning: S3_BUCKET not provided"
        echo "   CloudWatch monitoring will not be configured"
    fi
} || echo "⚠️  CloudWatch Agent installation failed (non-critical)" &

# Wait for all parallel jobs to complete
wait || true  # Continue even if some jobs failed

# Install Docker-dependent components
echo "Installing Pyxis (Slurm container plugin)..."

# Pyxis requires Slurm development headers which aren't included by default
# We'll try to install it, but it's optional - cluster works fine without it
(
    set +e  # Don't exit on error for Pyxis installation
    
    # Try to find Slurm installation directory
    SLURM_PREFIX="/opt/slurm"
    if [ ! -d "$SLURM_PREFIX" ]; then
        # Try alternative locations
        for dir in /usr /usr/local /opt/amazon/openmpi; do
            if [ -f "$dir/include/slurm/slurm.h" ]; then
                SLURM_PREFIX="$dir"
                break
            fi
        done
    fi
    
    if [ -f "$SLURM_PREFIX/include/slurm/slurm.h" ]; then
        echo "Found Slurm headers in $SLURM_PREFIX/include"
        
        cd /tmp
        git clone https://github.com/NVIDIA/pyxis.git
        cd pyxis
        
        # Build with custom Slurm path
        if make install CPPFLAGS="-I$SLURM_PREFIX/include" LDFLAGS="-L$SLURM_PREFIX/lib"; then
            echo "✓ Pyxis installation complete"
        else
            echo "⚠️  Pyxis build failed (non-critical)"
        fi
        
        cd /tmp
        rm -rf pyxis
    else
        echo "⚠️  Slurm headers not found - skipping Pyxis installation"
        echo "   This is optional - cluster will work without it"
        echo "   Impact: No native Slurm container support (can still use Docker directly)"
    fi
) || true  # Ensure script continues even if Pyxis fails

# DCGM Exporter (register as systemd service) - Optional for GPU instances
if [ "${ENABLE_DCGM_EXPORTER}" = "true" ]; then
    (
        set +e  # Don't exit on error
        echo "Configuring DCGM Exporter..."
        
        # Check if GPU is available
        if lspci | grep -i nvidia > /dev/null 2>&1; then
            cat > /etc/systemd/system/dcgm-exporter.service <<'EOF'
[Unit]
Description=NVIDIA DCGM Exporter
After=docker.service
Requires=docker.service

[Service]
ExecStartPre=-/usr/bin/docker stop dcgm-exporter
ExecStartPre=-/usr/bin/docker rm dcgm-exporter
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
            echo "✓ DCGM Exporter configured (port 9400)"
        else
            echo "⚠️  No GPU detected - skipping DCGM Exporter installation"
            echo "   This is normal for non-GPU compute nodes"
        fi
    ) || echo "⚠️  DCGM Exporter configuration failed (non-critical)"
else
    echo "DCGM Exporter installation disabled (ENABLE_DCGM_EXPORTER=false)"
fi

# Install Node Exporter (for system metrics) - Optional
if [ "${ENABLE_NODE_EXPORTER}" = "true" ]; then
    (
        set +e  # Don't exit on error
        echo "Installing Node Exporter..."
        NODE_EXPORTER_VERSION="1.7.0"
        wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
        rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

        cat > /etc/systemd/system/node-exporter.service <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable node-exporter
        systemctl start node-exporter
        echo "✓ Node Exporter configured (port 9100)"
    ) || echo "⚠️  Node Exporter installation failed (non-critical)"
else
    echo "Node Exporter installation disabled (ENABLE_NODE_EXPORTER=false)"
fi

# Install EFA Network Monitor (for GPU instances with EFA) - Optional
if [ "$SETUP_TYPE" = "gpu" ] && [ "${ENABLE_EFA_INSTALLER}" = "true" ]; then
    (
        set +e  # Don't exit on error
        echo "Setting up EFA Network Monitoring..."
        
        # Download EFA monitor scripts from S3
        if [ -n "${S3_BUCKET}" ]; then
            mkdir -p /opt/monitoring
            
            # Download Python monitor script
            aws s3 cp "s3://${S3_BUCKET}/config/monitoring/efa_network_monitor.py" /opt/monitoring/ --region ${REGION}
            
            # Download setup script
            aws s3 cp "s3://${S3_BUCKET}/config/monitoring/setup-efa-monitoring.sh" /tmp/ --region ${REGION}
            
            if [ -f "/opt/monitoring/efa_network_monitor.py" ] && [ -f "/tmp/setup-efa-monitoring.sh" ]; then
                chmod +x /tmp/setup-efa-monitoring.sh
                bash /tmp/setup-efa-monitoring.sh
                echo "✓ EFA Network Monitoring configured"
            else
                echo "⚠️  EFA monitoring scripts not found in S3"
                echo "   Upload scripts: aws s3 sync config/monitoring/ s3://${S3_BUCKET}/config/monitoring/"
            fi
        else
            echo "⚠️  S3_BUCKET not provided, skipping EFA monitoring"
        fi
    ) || echo "⚠️  EFA Network Monitoring setup failed (non-critical)"
else
    echo "EFA Network Monitoring disabled (not a GPU instance with EFA)"
fi

# CloudWatch Agent is already configured during installation above
echo "CloudWatch Agent configured during installation"

# Configure shared NCCL from FSx Lustre (if available)
(
    set +e  # Don't exit on error
    echo "Checking for shared NCCL installation..."
    
    if [ -f "/fsx/nccl/setup-nccl-env.sh" ]; then
        echo "Found shared NCCL, configuring environment..."
        
        # Add NCCL environment to system profile
        cat > /etc/profile.d/nccl-shared.sh << 'EOF'
# Shared NCCL configuration from FSx Lustre
source /fsx/nccl/setup-nccl-env.sh
EOF
        chmod +x /etc/profile.d/nccl-shared.sh
        
        # Source it now
        source /fsx/nccl/setup-nccl-env.sh
        
        echo "✓ Shared NCCL configured"
    else
        echo "⚠️  Shared NCCL not found in /fsx/nccl/"
        echo "   Install NCCL on HeadNode first:"
        echo "   bash /fsx/nccl/install-nccl-shared.sh v2.28.7-1 v1.17.2-aws /fsx"
    fi
) || echo "⚠️  NCCL configuration failed (non-critical)"

echo ""
echo "✓ Compute Node Setup Complete (${SETUP_TYPE} mode)"
echo "Installed components:"

if [ "$SETUP_TYPE" = "gpu" ]; then
    if [ "${ENABLE_EFA_INSTALLER}" = "true" ]; then
        echo "  - EFA Driver + libfabric"
    fi
    echo "  - Docker + NVIDIA Container Toolkit"
    echo "  - Pyxis (Slurm container plugin)"
    echo "  - CloudWatch Agent"
    if lspci | grep -i nvidia > /dev/null 2>&1; then
        echo "  - DCGM Exporter (port 9400) - GPU metrics"
    else
        echo "  - DCGM Exporter (skipped - no GPU detected)"
    fi
    echo "  - Node Exporter (port 9100) - System metrics"
    
    # Check if EFA monitoring is running
    if systemctl is-active --quiet efa-monitor.service 2>/dev/null; then
        echo "  - EFA Network Monitor - Inter-node network metrics"
    fi
    
    if [ -f "/fsx/nccl/setup-nccl-env.sh" ]; then
        echo "  - NCCL (shared from /fsx)"
    else
        echo ""
        echo "Note: NCCL not configured yet. Install on HeadNode:"
        echo "  ssh headnode"
        echo "  bash /fsx/nccl/install-nccl-shared.sh v2.28.7-1 v1.17.2-aws /fsx"
    fi
elif [ "$SETUP_TYPE" = "cpu" ]; then
    echo "  - Docker"
    echo "  - Pyxis (Slurm container plugin)"
    echo "  - CloudWatch Agent"
fi
if [ -n "${MONITORING_TYPE}" ] && [ "${MONITORING_TYPE}" != "none" ]; then
    if [ "${ENABLE_DCGM_EXPORTER}" = "true" ] || [ "${ENABLE_NODE_EXPORTER}" = "true" ]; then
        echo ""
        echo "Metrics collection: ${MONITORING_TYPE}"
        echo "  → Scraped by HeadNode Prometheus"
        if [ "${MONITORING_TYPE}" = "amp-only" ] || [ "${MONITORING_TYPE}" = "amp+amg" ]; then
            echo "  → Forwarded to AWS Managed Prometheus"
        fi
    fi
fi
