#!/bin/bash
# Setup EFA Network Monitoring
# This script is called from compute node setup for GPU instances only

set -e

echo "=== Setting up EFA Network Monitoring ==="

# Check if EFA interfaces exist
if [ ! -d "/sys/class/infiniband" ] || [ -z "$(ls -A /sys/class/infiniband 2>/dev/null)" ]; then
    echo "⚠️  No EFA interfaces found, skipping EFA monitoring"
    exit 0
fi

echo "✓ EFA interfaces detected"

# Create monitoring directory
mkdir -p /opt/monitoring

# Copy Python script (should be downloaded from S3)
if [ ! -f "/opt/monitoring/efa_network_monitor.py" ]; then
    echo "⚠️  EFA monitor script not found at /opt/monitoring/efa_network_monitor.py"
    exit 1
fi

chmod +x /opt/monitoring/efa_network_monitor.py

# Install boto3 if not present
if ! python3 -c "import boto3" 2>/dev/null; then
    echo "Installing boto3..."
    pip3 install boto3
fi

# Create systemd service
cat > /etc/systemd/system/efa-monitor.service << 'EOF'
[Unit]
Description=EFA Network Performance Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/monitoring/efa_network_monitor.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/efa_monitor.log
StandardError=append:/var/log/efa_monitor.log
User=root

# Resource limits (low overhead)
CPUQuota=5%
MemoryLimit=256M

[Install]
WantedBy=multi-user.target
EOF

# Setup log rotation
cat > /etc/logrotate.d/efa-monitor << 'EOF'
/var/log/efa_monitor.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 root root
}
EOF

# Start service
systemctl daemon-reload
systemctl enable efa-monitor.service
systemctl start efa-monitor.service

# Wait and check status
sleep 3
if systemctl is-active --quiet efa-monitor.service; then
    echo "✓ EFA monitoring service started successfully"
    echo "  Logs: /var/log/efa_monitor.log"
    echo "  Status: systemctl status efa-monitor"
else
    echo "⚠️  EFA monitoring service failed to start"
    systemctl status efa-monitor.service || true
    exit 1
fi

echo "=== EFA Monitoring Setup Complete ==="
