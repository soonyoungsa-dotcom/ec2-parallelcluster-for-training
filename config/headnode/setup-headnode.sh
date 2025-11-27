#!/bin/bash
# Head Node Setup Script
# Cluster management + metrics collection: CloudWatch Agent + Prometheus

# Don't exit on error - continue even if individual components fail
set +e

CLUSTER_NAME="${1:-my-cluster}"
REGION="${2:-us-east-1}"
S3_BUCKET="${3}"
MONITORING_TYPE="${4:-self-hosting}"  # Monitoring type from environment variables
AMP_ENDPOINT="${5}"  # AMP endpoint (only if MONITORING_TYPE is amp-only or amp+amg)

echo "=== Head Node Setup Started ==="
echo "Cluster Name: ${CLUSTER_NAME}"
echo "Region: ${REGION}"
echo "Monitoring Type: ${MONITORING_TYPE}"

# Validate AMP configuration if needed
if [ "${MONITORING_TYPE}" = "amp-only" ] || [ "${MONITORING_TYPE}" = "amp+amg" ]; then
    if [ -z "${AMP_ENDPOINT}" ]; then
        echo "⚠️  WARNING: AMP monitoring configured but endpoint not provided"
        echo "   MonitoringType: ${MONITORING_TYPE}"
        echo "   AMP Endpoint: (not provided as 5th argument)"
        echo "   Falling back to self-hosting mode"
        MONITORING_TYPE="self-hosting"
    else
        echo "AMP Endpoint: ${AMP_ENDPOINT}"
    fi
fi

# Install CloudWatch Agent and Slurm Metrics Collector
(
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
        
        # Install Slurm metrics collector
        aws s3 cp "s3://${S3_BUCKET}/config/cloudwatch/install-slurm-metrics.sh" /tmp/ --region ${REGION}
        if [ -f "/tmp/install-slurm-metrics.sh" ]; then
            chmod +x /tmp/install-slurm-metrics.sh
            bash /tmp/install-slurm-metrics.sh "${CLUSTER_NAME}" "${REGION}" "${S3_BUCKET}"
        else
            echo "⚠️  Slurm metrics collector installation script not found"
        fi
    else
        echo "⚠️  Warning: S3_BUCKET not provided"
        echo "   CloudWatch monitoring will not be configured"
    fi
) || echo "⚠️  CloudWatch Agent installation/configuration failed (non-critical)"

# Install Prometheus based on monitoring type
(
    set +e  # Don't exit on error
    if [ "${MONITORING_TYPE}" = "self-hosting" ]; then
    echo "Installing Prometheus (self-hosting mode)..."
    PROMETHEUS_VERSION="2.45.0"
    wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 /opt/prometheus
    rm -f prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

    # Prometheus config - Compute nodes auto-discovery
    cat > /opt/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # DCGM Exporter from Compute Nodes
  - job_name: 'dcgm'
    ec2_sd_configs:
      - region: REGION_PLACEHOLDER
        filters:
          - name: tag:aws:parallelcluster:node-type
            values: [Compute]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '${1}:9400'
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

  # Node Exporter from Compute Nodes
  - job_name: 'compute-nodes'
    ec2_sd_configs:
      - region: REGION_PLACEHOLDER
        filters:
          - name: tag:aws:parallelcluster:node-type
            values: [Compute]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '${1}:9100'
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
EOF

    # Replace region placeholder
    sed -i "s/REGION_PLACEHOLDER/${REGION}/g" /opt/prometheus/prometheus.yml

    # Create Prometheus systemd service
    cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --web.listen-address=:9090
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Start Prometheus
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    echo "✓ Prometheus installed (self-hosting mode, port 9090)"

elif [ "${MONITORING_TYPE}" = "amp-only" ] || [ "${MONITORING_TYPE}" = "amp+amg" ]; then
    echo "Installing Prometheus with AMP remote_write (${MONITORING_TYPE} mode)..."
    
    # AMP_ENDPOINT is already validated at the beginning of the script
    PROMETHEUS_VERSION="2.45.0"
    wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 /opt/prometheus
    rm -f prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

    # Prometheus config with AMP remote_write
    cat > /opt/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # DCGM Exporter from Compute Nodes
  - job_name: 'dcgm'
    ec2_sd_configs:
      - region: ${REGION}
        filters:
          - name: tag:aws:parallelcluster:node-type
            values: [Compute]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:9400'
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

  # Node Exporter from Compute Nodes
  - job_name: 'compute-nodes'
    ec2_sd_configs:
      - region: ${REGION}
        filters:
          - name: tag:aws:parallelcluster:node-type
            values: [Compute]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:9100'
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id

# Remote write to AWS Managed Prometheus
remote_write:
  - url: ${AMP_ENDPOINT}api/v1/remote_write
    queue_config:
      max_samples_per_send: 1000
      max_shards: 200
      capacity: 2500
    sigv4:
      region: ${REGION}
EOF

    # Create Prometheus systemd service
    cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus with AMP remote_write
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --web.listen-address=:9090 \
  --storage.tsdb.retention.time=1h
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Start Prometheus
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    echo "✓ Prometheus installed with AMP remote_write (${MONITORING_TYPE} mode)"
    echo "  - Local retention: 1 hour"
    echo "  - Remote write to: ${AMP_ENDPOINT}"
fi

# Handle self-hosting mode (including fallback cases)
if [ "${MONITORING_TYPE}" = "self-hosting" ]; then
    echo "Installing Prometheus (self-hosting mode)..."
    PROMETHEUS_VERSION="2.45.0"
    wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 /opt/prometheus
    rm -f prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

    # Prometheus config - Compute nodes auto-discovery
    cat > /opt/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # DCGM Exporter from Compute Nodes
  - job_name: 'dcgm'
    ec2_sd_configs:
      - region: ${REGION}
        filters:
          - name: tag:aws:parallelcluster:node-type
            values: [Compute]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:9400'
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

  # Node Exporter from Compute Nodes
  - job_name: 'compute-nodes'
    ec2_sd_configs:
      - region: ${REGION}
        filters:
          - name: tag:aws:parallelcluster:node-type
            values: [Compute]
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '\${1}:9100'
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
EOF

    # Create Prometheus systemd service
    cat > /etc/systemd/system/prometheus.service <<'EOFSERVICE'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --web.listen-address=:9090
Restart=always

[Install]
WantedBy=multi-user.target
EOFSERVICE

    # Start Prometheus
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    echo "✓ Prometheus installed (self-hosting mode, port 9090)"
    elif [ "${MONITORING_TYPE}" = "none" ]; then
        echo "Monitoring disabled (monitoring type: none)"
    fi
) || echo "⚠️  Prometheus installation failed (non-critical)"

# Initialize FSx Lustre directory structure
(
    set +e  # Don't exit on error
    echo ""
    echo "=========================================="
    echo "FSx Lustre Initialization"
    echo "=========================================="
    
    # Verify FSx Lustre is mounted
    if ! mountpoint -q /fsx; then
        echo "⚠️  /fsx not mounted, skipping initialization"
        exit 0
    fi
    
    echo "✓ FSx Lustre mounted at /fsx"
    
    # Create directory structure
    echo "Creating directory structure..."
    mkdir -p /fsx/{containers,scripts,config,logs,nccl,datasets,checkpoints,results}
    mkdir -p /fsx/logs/{container-downloads,slurm,training}
    mkdir -p /fsx/containers/{runtime,cache,data}
    
    echo "✓ Directory structure created:"
    echo "  /fsx/containers/     - NGC container images"
    echo "  /fsx/scripts/        - Shared scripts"
    echo "  /fsx/config/         - Configuration files"
    echo "  /fsx/logs/           - Log files"
    echo "  /fsx/nccl/           - NCCL installation (manual)"
    echo "  /fsx/datasets/       - Training datasets"
    echo "  /fsx/checkpoints/    - Model checkpoints"
    echo "  /fsx/results/        - Training results"
    
) || echo "⚠️  FSx initialization failed (non-critical)"

# Download NGC containers to FSx Lustre (background job)
(
    set +e  # Don't exit on error
    echo ""
    echo "=========================================="
    echo "NGC Container Setup"
    echo "=========================================="
    
    # Copy container list and download script to FSx
    if [ -n "${S3_BUCKET}" ]; then
        echo "Downloading NGC container scripts from S3..."
        
        # Download scripts
        aws s3 cp "s3://${S3_BUCKET}/config/headnode/download-ngc-containers.sh" /fsx/scripts/ 2>/dev/null || {
            echo "⚠️  download-ngc-containers.sh not found in S3"
        }
        
        aws s3 cp "s3://${S3_BUCKET}/config/headnode/containers.txt" /fsx/config/ 2>/dev/null || {
            echo "⚠️  containers.txt not found in S3"
        }
        
        chmod +x /fsx/scripts/*.sh 2>/dev/null
    fi
    
    # Check if download script exists
    if [ -f "/fsx/scripts/download-ngc-containers.sh" ]; then
        echo ""
        echo "Starting NGC container download (background)..."
        echo "This will download containers to /fsx/containers/"
        echo "Progress can be monitored at: /fsx/logs/container-downloads/"
        echo ""
        
        # Run in background to avoid blocking cluster creation
        nohup bash /fsx/scripts/download-ngc-containers.sh /fsx/config/containers.txt \
            > /fsx/logs/ngc-download.log 2>&1 &
        
        NGC_PID=$!
        echo "✓ NGC container download started (PID: ${NGC_PID})"
        echo "  Log: /fsx/logs/ngc-download.log"
        echo "  Containers will be available at: /fsx/containers/"
        echo ""
        echo "To check progress:"
        echo "  tail -f /fsx/logs/ngc-download.log"
        echo "  ls -lh /fsx/containers/"
    else
        echo "⚠️  NGC download script not found"
        echo "   Containers can be downloaded manually:"
        echo "   1. Upload scripts to S3:"
        echo "      aws s3 cp config/headnode/download-ngc-containers.sh s3://${S3_BUCKET}/config/headnode/"
        echo "      aws s3 cp config/headnode/containers.txt s3://${S3_BUCKET}/config/headnode/"
        echo "   2. On HeadNode:"
        echo "      bash /fsx/scripts/download-ngc-containers.sh"
    fi
    
    echo "=========================================="
) || echo "⚠️  NGC container setup failed (non-critical)"

echo ""
echo "✓ Head Node Setup Complete"
echo "Installed components:"
echo "  - CloudWatch Agent"
if [ "${MONITORING_TYPE}" != "none" ]; then
    echo "  - Prometheus (port 9090) - ${MONITORING_TYPE} mode"
    echo "  - Auto-discovery for Compute Node metrics"
fi
echo "  - NGC container download (background)"
echo ""
echo "NGC Containers:"
echo "  - Download in progress (background)"
echo "  - Location: /fsx/containers/"
echo "  - Check progress: tail -f /fsx/logs/ngc-download.log"
echo "  - List containers: /fsx/containers/list-containers.sh"

# Create CloudWatch Dashboards (background)
(
    set +e  # Don't exit on error
    echo ""
    echo "=========================================="
    echo "CloudWatch Dashboard Creation"
    echo "=========================================="
    
    if [ -n "${S3_BUCKET}" ]; then
        # Wait a bit for the instance to be fully registered
        echo "Waiting 30 seconds for instance registration..."
        sleep 30
        
        # Download dashboard creation scripts
        aws s3 cp "s3://${S3_BUCKET}/config/cloudwatch/create-dashboard.sh" /tmp/ --region ${REGION}
        aws s3 cp "s3://${S3_BUCKET}/config/cloudwatch/create-advanced-dashboard.sh" /tmp/ --region ${REGION}
        
        if [ -f "/tmp/create-dashboard.sh" ] && [ -f "/tmp/create-advanced-dashboard.sh" ]; then
            chmod +x /tmp/create-dashboard.sh /tmp/create-advanced-dashboard.sh
            
            echo "Creating CloudWatch dashboards..."
            
            # Create basic dashboard
            bash /tmp/create-dashboard.sh "${CLUSTER_NAME}" "${REGION}" > /var/log/dashboard-creation.log 2>&1
            if [ $? -eq 0 ]; then
                echo "✓ Basic dashboard created"
            else
                echo "⚠️  Basic dashboard creation failed (check /var/log/dashboard-creation.log)"
            fi
            
            # Create advanced dashboard
            bash /tmp/create-advanced-dashboard.sh "${CLUSTER_NAME}" "${REGION}" >> /var/log/dashboard-creation.log 2>&1
            if [ $? -eq 0 ]; then
                echo "✓ Advanced dashboard created"
            else
                echo "⚠️  Advanced dashboard creation failed (check /var/log/dashboard-creation.log)"
            fi
            
            # Create EFA dashboard
            aws s3 cp "s3://${S3_BUCKET}/config/cloudwatch/create-efa-dashboard.sh" /tmp/ --region ${REGION}
            if [ -f "/tmp/create-efa-dashboard.sh" ]; then
                chmod +x /tmp/create-efa-dashboard.sh
                bash /tmp/create-efa-dashboard.sh "${CLUSTER_NAME}" "${REGION}" >> /var/log/dashboard-creation.log 2>&1
                if [ $? -eq 0 ]; then
                    echo "✓ EFA dashboard created"
                else
                    echo "⚠️  EFA dashboard creation failed (check /var/log/dashboard-creation.log)"
                fi
            fi
            
            echo ""
            echo "Dashboard URLs:"
            echo "  Basic: https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=ParallelCluster-${CLUSTER_NAME}"
            echo "  Advanced: https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=ParallelCluster-${CLUSTER_NAME}-Advanced"
            echo "  EFA Network: https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=ParallelCluster-${CLUSTER_NAME}-EFA"
        else
            echo "⚠️  Dashboard creation scripts not found in S3"
            echo "   You can create dashboards manually later:"
            echo "   bash config/cloudwatch/create-dashboard.sh ${CLUSTER_NAME} ${REGION}"
            echo "   bash config/cloudwatch/create-advanced-dashboard.sh ${CLUSTER_NAME} ${REGION}"
        fi
    else
        echo "⚠️  S3_BUCKET not provided, skipping dashboard creation"
    fi
    
    echo "=========================================="
) &  # Run in background to not block cluster creation

echo ""
echo "Note: CloudWatch dashboards are being created in the background"
echo "      Check /var/log/dashboard-creation.log for status"
