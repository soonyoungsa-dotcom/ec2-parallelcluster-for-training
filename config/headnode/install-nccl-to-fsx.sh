#!/bin/bash
set -e

# NCCL Installation Script for FSx Lustre
# This script installs NCCL to /fsx for shared access across all compute nodes

NCCL_VERSION="v2.20.5-1"
INSTALL_DIR="/fsx/nccl"
BUILD_DIR="/tmp/nccl-build"

echo "=== Installing NCCL to FSx Lustre ==="
echo "Version: ${NCCL_VERSION}"
echo "Install directory: ${INSTALL_DIR}"

# Check if /fsx is mounted
if ! mountpoint -q /fsx; then
    echo "ERROR: /fsx is not mounted"
    exit 1
fi

# Check if CUDA is available
if [ ! -d "/usr/local/cuda" ]; then
    echo "ERROR: CUDA not found at /usr/local/cuda"
    exit 1
fi

# Create build directory
mkdir -p ${BUILD_DIR}
cd ${BUILD_DIR}

# Download NCCL
echo "Downloading NCCL ${NCCL_VERSION}..."
wget -q https://github.com/NVIDIA/nccl/archive/refs/tags/${NCCL_VERSION}.tar.gz
tar -xzf ${NCCL_VERSION}.tar.gz
cd nccl-${NCCL_VERSION#v}

# Build NCCL
echo "Building NCCL..."
make -j$(nproc) src.build CUDA_HOME=/usr/local/cuda

# Install to FSx
echo "Installing NCCL to ${INSTALL_DIR}..."
make install PREFIX=${INSTALL_DIR}

# Create environment setup script
cat > ${INSTALL_DIR}/nccl-env.sh << 'EOF'
#!/bin/bash
# Source this file to set up NCCL environment
export LD_LIBRARY_PATH=/fsx/nccl/lib:$LD_LIBRARY_PATH
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=ALL
EOF

chmod +x ${INSTALL_DIR}/nccl-env.sh

# Cleanup
cd /
rm -rf ${BUILD_DIR}

echo "=== NCCL Installation Complete ==="
echo "NCCL installed to: ${INSTALL_DIR}"
echo "To use NCCL, run: source ${INSTALL_DIR}/nccl-env.sh"
echo ""
echo "Library path: ${INSTALL_DIR}/lib"
echo "Include path: ${INSTALL_DIR}/include"
