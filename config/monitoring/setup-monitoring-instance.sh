#!/bin/bash
# Monitoring Instance Setup Script
# Grafana + Prometheus 설치 및 설정
#
# ⚠️ 주의: 이 스크립트는 실제 배포에서 사용되지 않습니다!
#
# Monitoring Instance는 parallelcluster-infrastructure.yaml의 UserData를 통해
# 자동으로 설치됩니다. 이 스크립트는 다음 경우에만 사용하세요:
#
# 1. 참고용: UserData 스크립트와 비교하여 설정 확인
# 2. 수동 재설치: 모니터링 스택을 완전히 재설치해야 하는 경우
# 3. 커스터마이징: UserData 방식이 아닌 수동 설치가 필요한 경우
#
# 사용법:
#   bash setup-monitoring-instance.sh <region> <head-node-ip>
#
# 예시:
#   bash setup-monitoring-instance.sh us-east-2 10.0.1.100

set -e

REGION="${1:-us-east-1}"
HEAD_NODE_IP="${2}"

echo "=== Monitoring Instance Setup Started ==="
echo "Region: ${REGION}"
echo "Head Node IP: ${HEAD_NODE_IP}"

# Install Docker and Docker Compose (Amazon Linux)
echo "Installing Dock..."er
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create monitoring directory
mkdir -p /opt/monitoring
cd /opt/monitoring

# Docker Compose configuration
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s:%(http_port)s/
      - GF_SERVER_SERVE_FROM_SUB_PATH=false
    volumes:
      - grafana-storage:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    networks:
      - monitoring
  
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: always
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--storage.tsdb.retention.time=30d'
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-storage:/prometheus
    networks:
      - monitoring

volumes:
  grafana-storage:
  prometheus-storage:

networks:
  monitoring:
    driver: bridge
EOF

# Prometheus config directory
mkdir -p prometheus

# Prometheus config (using Head Node Prometheus as data source)
cat > prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'parallelcluster'
    region: '${REGION}'

scrape_configs:
  # Self monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Head Node Prometheus (federation)
  - job_name: 'head-node-prometheus'
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~"dcgm|compute-nodes"}'
    static_configs:
      - targets: ['${HEAD_NODE_IP}:9090']
        labels:
          source: 'head-node'
EOF

# Grafana provisioning directories
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards

# Grafana datasource configuration
cat > grafana/provisioning/datasources/datasources.yml <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: 15s
  
  - name: CloudWatch
    type: cloudwatch
    jsonData:
      authType: default
      defaultRegion: ${REGION}
    editable: true
EOF

# Grafana dashboard provisioning configuration
cat > grafana/provisioning/dashboards/dashboards.yml <<'EOF'
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Start services
echo "Starting Grafana and Prometheus..."
docker-compose up -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 15

# Check status
echo "Checking service status..."
docker-compose ps

# Print access information
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo ""
echo "✓ Monitoring Instance Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Access Information:"
echo "  - Grafana (external): http://${PUBLIC_IP}:3000"
echo "  - Grafana (internal): http://${PRIVATE_IP}:3000"
echo "  - Prometheus (external): http://${PUBLIC_IP}:9090"
echo "  - Prometheus (internal): http://${PRIVATE_IP}:9090"
echo ""
echo "Grafana Login:"
echo "  - Username: admin"
echo "  - Password: admin (change on first login)"
echo ""
echo "Data Sources:"
echo "  - Prometheus: Metrics from Head Node"
echo "  - CloudWatch: AWS metrics and logs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create health check script
cat > /opt/monitoring/healthcheck.sh <<'HEALTHCHECK'
#!/bin/bash
echo "=== Monitoring Services Health Check ==="
echo ""
echo "Docker Compose Status:"
docker-compose -f /opt/monitoring/docker-compose.yml ps
echo ""
echo "Grafana Health:"
curl -s http://localhost:3000/api/health | jq . || echo "Grafana not responding"
echo ""
echo "Prometheus Health:"
curl -s http://localhost:9090/-/healthy || echo "Prometheus not responding"
HEALTHCHECK

chmod +x /opt/monitoring/healthcheck.sh

echo ""
echo "Run health check: /opt/monitoring/healthcheck.sh"
