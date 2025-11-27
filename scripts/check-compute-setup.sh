#!/bin/bash
#
# Check ComputeNode setup status
# Run this on ComputeNode to verify installation
# Usage: srun --nodes=1 bash /fsx/scripts/check-compute-setup.sh

echo "=========================================="
echo "ComputeNode Setup Status"
echo "=========================================="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

check_component() {
    local name="$1"
    local check_cmd="$2"
    local detail_cmd="$3"
    
    printf "%-30s" "$name: "
    
    if eval "$check_cmd" &>/dev/null; then
        echo -e "${GREEN}✓ Installed${NC}"
        if [ -n "$detail_cmd" ]; then
            eval "$detail_cmd" 2>/dev/null | sed 's/^/  /'
        fi
    else
        echo -e "${RED}✗ Not installed${NC}"
    fi
}

check_service() {
    local name="$1"
    local service="$2"
    
    printf "%-30s" "$name: "
    
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓ Running${NC}"
        systemctl status "$service" --no-pager -l | grep "Active:" | sed 's/^/  /'
    else
        echo -e "${RED}✗ Not running${NC}"
    fi
}

echo "=== System Information ==="
check_component "OS" "true" "cat /etc/os-release | grep PRETTY_NAME"
check_component "Kernel" "true" "uname -r"
check_component "Uptime" "true" "uptime -p"
echo ""

echo "=== FSx Lustre ==="
check_component "FSx mounted" "mountpoint -q /fsx" "df -h /fsx | tail -1"
echo ""

echo "=== GPU & Drivers ==="
check_component "NVIDIA Driver" "command -v nvidia-smi" "nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1"
check_component "CUDA" "command -v nvcc" "nvcc --version | grep release"
check_component "GPU Count" "command -v nvidia-smi" "nvidia-smi --query-gpu=count --format=csv,noheader | head -1"
echo ""

echo "=== EFA ==="
check_component "EFA Installer" "[ -f /opt/amazon/efa_installed_packages ]" "cat /opt/amazon/efa_installed_packages | head -5"
check_component "Libfabric" "[ -f /opt/amazon/efa/bin/fi_info ]" "/opt/amazon/efa/bin/fi_info --version 2>&1 | head -1"
check_component "EFA Devices" "ls /dev/infiniband/ 2>/dev/null" "ls -la /dev/infiniband/ 2>/dev/null | tail -n +4"
echo ""

echo "=== Container Runtime ==="
check_component "Docker" "command -v docker" "docker --version"
check_component "NVIDIA Container Toolkit" "command -v nvidia-container-cli" "nvidia-container-cli --version"
check_component "Enroot" "command -v enroot" "enroot version"
check_component "Pyxis" "[ -f /usr/local/lib/slurm/spank_pyxis.so ]" "ls -lh /usr/local/lib/slurm/spank_pyxis.so 2>/dev/null"
echo ""

echo "=== Monitoring ==="
check_component "CloudWatch Agent" "[ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]" "echo 'Installed'"
check_service "DCGM Exporter" "dcgm-exporter"
check_service "Node Exporter" "node-exporter"
echo ""

echo "=== NCCL ==="
check_component "NCCL Profile Script" "[ -f /etc/profile.d/nccl-shared.sh ]" "cat /etc/profile.d/nccl-shared.sh"
if [ -f /etc/profile.d/nccl-shared.sh ]; then
    source /etc/profile.d/nccl-shared.sh
    check_component "NCCL Version" "[ -n \"$NCCL_VERSION\" ]" "echo $NCCL_VERSION"
    check_component "NCCL Library Path" "[ -n \"$LD_LIBRARY_PATH\" ]" "echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -E 'nccl|cuda' | head -3"
fi
echo ""

echo "=== Network ==="
check_component "Network Interfaces" "true" "ip -br addr show | grep -v lo"
check_component "EFA Interface" "ip link show | grep -q efa" "ip -br addr show | grep efa"
echo ""

echo "=== Slurm ==="
check_component "Slurm Version" "command -v srun" "srun --version"
check_component "Slurm Node State" "command -v sinfo" "sinfo -N -n $(hostname) -o '%N %T %E'"
echo ""

echo "=========================================="
echo "Setup Summary"
echo "=========================================="

TOTAL=0
INSTALLED=0

# Count installed components
for cmd in nvidia-smi docker nvidia-container-cli; do
    TOTAL=$((TOTAL + 1))
    if command -v $cmd &>/dev/null; then
        INSTALLED=$((INSTALLED + 1))
    fi
done

# Check services
for service in dcgm-exporter node-exporter; do
    TOTAL=$((TOTAL + 1))
    if systemctl is-active --quiet $service; then
        INSTALLED=$((INSTALLED + 1))
    fi
done

# Check files
for file in /opt/amazon/efa_installed_packages /etc/profile.d/nccl-shared.sh; do
    TOTAL=$((TOTAL + 1))
    if [ -f $file ]; then
        INSTALLED=$((INSTALLED + 1))
    fi
done

PERCENTAGE=$((INSTALLED * 100 / TOTAL))

echo ""
echo "Installation Progress: ${INSTALLED}/${TOTAL} components (${PERCENTAGE}%)"
echo ""

if [ $PERCENTAGE -eq 100 ]; then
    echo -e "${GREEN}✓ All components installed successfully!${NC}"
elif [ $PERCENTAGE -ge 80 ]; then
    echo -e "${YELLOW}⚠️  Most components installed (some optional components missing)${NC}"
else
    echo -e "${RED}❌ Installation incomplete or in progress${NC}"
fi

echo ""
echo "=========================================="
