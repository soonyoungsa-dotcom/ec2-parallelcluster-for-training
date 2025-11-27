# AMP + AMG Automatic Connection Guide

This is a guide for setting up a fully managed monitoring solution using AWS Managed Prometheus (AMP) and AWS Managed Grafana (AMG).

## 📋 Table of Contents

- [Automated Tasks](#automated-tasks)
- [Manual Tasks](#manual-tasks)
- [Full Setup Process](#full-setup-process)
- [Accessing Grafana](#accessing-grafana)
- [Troubleshooting](#troubleshooting)

## ✅ Automated Tasks

The following tasks are automatically performed during Infrastructure stack deployment:

### 1. AMP Workspace Creation
- ✅ Prometheus workspace is automatically created
- ✅ Remote write endpoint is configured
- ✅ IAM policies are automatically created (remote_write, query)

### 2. AMG Workspace Creation
- ✅ Grafana workspace is automatically created
- ✅ AWS SSO authentication is set up
- ✅ IAM role is automatically created

### 3. AMP ↔ AMG Automatic Connection
- ✅ Lambda function automatically adds the AMP data source to Grafana
- ✅ SigV4 authentication is automatically set up
- ✅ Set as the default data source

### 4. ParallelCluster Integration
- ✅ HeadNode Prometheus sends metrics to AMP
- ✅ IAM policy is automatically attached

## 🔧 Manual Tasks

### 1. Configure AWS IAM Identity Center (SSO)

**Prerequisite**: AWS IAM Identity Center must be enabled.

```bash
# Check if Identity Center is enabled
aws sso-admin list-instances --region us-east-2
```

**If not enabled:**
1. Go to AWS Console → IAM Identity Center
2. Click "Enable"
3. Set up your organization's email

### 2. Add Grafana Users

After deploying the Infrastructure stack:

```bash
# 1. Get the Grafana Workspace ID
GRAFANA_WORKSPACE_ID=$(aws cloudformation describe-stacks \
    --stack-name pcluster-infra \
    --region us-east-2 \
    --query 'Stacks[0].Outputs[?OutputKey==`ManagedGrafanaWorkspaceId`].OutputValue' \
    --output text)

echo "Grafana Workspace ID: ${GRAFANA_WORKSPACE_ID}"

# 2. Grant ADMIN permissions to a user
aws grafana update-permissions \
    --workspace-id ${GRAFANA_WORKSPACE_ID} \
    --region us-east-2 \
    --update-instruction-batch '[
        {
            "action": "ADD",
            "role": "ADMIN",
            "users": [
                {
                    "id": "your-email@example.com",
                    "type": "SSO_USER"
                }
            ]
        }
    ]'
```

**Role options:**
- `ADMIN`: Full permissions (create/modify/delete dashboards)
- `EDITOR`: Create/modify dashboards
- `VIEWER`: Read-only

### 3. Add Multiple Users

```bash
# Add multiple users at once
aws grafana update-permissions \
    --workspace-id ${GRAFANA_WORKSPACE_ID} \
    --region us-east-2 \
    --update-instruction-batch '[
        {
            "action": "ADD",
            "role": "ADMIN",
            "users": [
                {"id": "admin@example.com", "type": "SSO_USER"}
            ]
        },
        {
            "action": "ADD",
            "role": "EDITOR",
            "users": [
                {"id": "engineer1@example.com", "type": "SSO_USER"},
                {"id": "engineer2@example.com", "type": "SSO_USER"}
            ]
        },
        {
            "action": "ADD",
            "role": "VIEWER",
            "users": [
                {"id": "viewer@example.com", "type": "SSO_USER"}
            ]
        }
    ]'
```

## 🚀 Full Setup Process

### Step 1: Deploy the Infrastructure Stack

```bash
# Set MonitoringType to amp+amg
aws cloudformation create-stack \
    --stack-name pcluster-infra \
    --template-body file://parallelcluster-infrastructure.yaml \
    --parameters \
        ParameterKey=MonitoringType,ParameterValue=amp+amg \
        ParameterKey=VPCName,ParameterValue=pcluster-vpc \
        ParameterKey=PrimarySubnetAZ,ParameterValue=us-east-2a \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-2
```

**Automated Tasks:**
- AMP Workspace creation (~1 minute)
- AMG Workspace creation (~5 minutes)
- Lambda function adds AMP data source to Grafana (~1 minute)

### Step 2: Wait for Stack Completion

```bash
# Wait for stack creation to complete (around 5-10 minutes)
aws cloudformation wait stack-create-complete \
    --stack-name pcluster-infra \
    --region us-east-2

echo "✓ Infrastructure stack created successfully"
```

### Step 3: Retrieve Grafana Access Information

```bash
# Get the Grafana URL
GRAFANA_URL=$(aws cloudformation describe-stacks \
    --stack-name pcluster-infra \
    --region us-east-2 \
    --query 'Stacks[0].Outputs[?OutputKey==`ManagedGrafanaWorkspaceEndpoint`].OutputValue' \
    --output text)

echo "Grafana URL: https://${GRAFANA_URL}"

# Get the Workspace ID
GRAFANA_WORKSPACE_ID=$(aws cloudformation describe-stacks \
    --stack-name pcluster-infra \
    --region us-east-2 \
    --query 'Stacks[0].Outputs[?OutputKey==`ManagedGrafanaWorkspaceId`].OutputValue' \
    --output text)

echo "Workspace ID: ${GRAFANA_WORKSPACE_ID}"
```

### Step 4: Add Users (Manual)

```bash
# Add yourself as an ADMIN
aws grafana update-permissions \
    --workspace-id ${GRAFANA_WORKSPACE_ID} \
    --region us-east-2 \
    --update-instruction-batch '[
        {
            "action": "ADD",
            "role": "ADMIN",
            "users": [
                {
                    "id": "your-email@example.com",
                    "type": "SSO_USER"
                }
            ]
        }
    ]'

echo "✓ User added to Grafana workspace"
```

### Step 5: Create ParallelCluster

```bash
# Check CLUSTER_NAME in environment-variables-bailey.sh
source environment-variables-bailey.sh

# Create the cluster
pcluster create-cluster \
    --cluster-name ${CLUSTER_NAME} \
    --cluster-configuration cluster-config.yaml \
    --region ${AWS_REGION}
```

**Automated Tasks:**
- HeadNode Prometheus sends metrics to AMP
- ComputeNode DCGM/Node Exporter sends metrics to HeadNode Prometheus
- Prometheus sends remote_write to AMP

## 🌐 Accessing Grafana

### 1. Access the Grafana URL

```bash
# Get the URL
aws cloudformation describe-stacks \
    --stack-name pcluster-infra \
    --region us-east-2 \
    --query 'Stacks[0].Outputs[?OutputKey==`ManagedGrafanaWorkspaceEndpoint`].OutputValue' \
    --output text
```

Open the URL `https://<workspace-id>.grafana-workspace.us-east-2.amazonaws.com` in your browser.

### 2. Sign in with AWS SSO

1. Click "Sign in with AWS SSO"
2. Enter your Identity Center email/password
3. Perform MFA (if configured)

### 3. Verify the AMP Data Source

After logging into Grafana:
1. Go to the left menu → Configuration → Data sources
2. Verify the "Amazon Managed Prometheus" data source
3. Ensure the "Default" tag is set

### 4. Create a Dashboard

```
1. Go to the left menu → Create → Dashboard
2. Add a panel
3. Query: Select a metric (e.g., up, node_cpu_seconds_total)
4. Data source: Amazon Managed Prometheus (automatically selected)
5. Save the dashboard
```

## 📊 Pre-Configured Metrics

Metrics automatically collected in AMP:

### DCGM (GPU Metrics)
- `DCGM_FI_DEV_GPU_UTIL` - GPU utilization
- `DCGM_FI_DEV_MEM_COPY_UTIL` - GPU memory utilization
- `DCGM_FI_DEV_GPU_TEMP` - GPU temperature
- `DCGM_FI_DEV_POWER_USAGE` - GPU power usage

### Node Exporter (System Metrics)
- `node_cpu_seconds_total` - CPU usage time
- `node_memory_MemAvailable_bytes` - Available memory
- `node_disk_io_time_seconds_total` - Disk I/O
- `node_network_receive_bytes_total` - Network receive

### Slurm Metrics (Collected from CloudWatch)
- Available in CloudWatch
- Can be queried in Grafana using the CloudWatch data source

## 🛠️ Troubleshooting

### Issue: Unable to access Grafana

**Cause**: User is not added to the Grafana workspace

**Solution:**
```bash
# Check the list of users
aws grafana list-permissions \
    --workspace-id ${GRAFANA_WORKSPACE_ID} \
    --region us-east-2

# Add the user
aws grafana update-permissions \
    --workspace-id ${GRAFANA_WORKSPACE_ID} \
    --region us-east-2 \
    --update-instruction-batch '[{"action":"ADD","role":"ADMIN","users":[{"id":"your-email@example.com","type":"SSO_USER"}]}]'
```

### Issue: AMP Data Source missing in Grafana

**Cause**: Lambda function execution failed

**Solution:**
```bash
# Check the Lambda logs
aws logs tail /aws/lambda/pcluster-infra-grafana-datasource-setup \
    --region us-east-2 \
    --follow

# Manually re-run the Lambda function
aws lambda invoke \
    --function-name pcluster-infra-grafana-datasource-setup \
    --region us-east-2 \
    /tmp/lambda-output.json

cat /tmp/lambda-output.json
```

### Issue: Metrics not visible in Grafana

**Cause**: HeadNode Prometheus is not sending metrics to AMP

**Solution:**
```bash
# Check the Prometheus status on the HeadNode
ssh headnode
sudo systemctl status prometheus

# Verify the Prometheus configuration
cat /opt/prometheus/prometheus.yml | grep -A10 remote_write

# Check the AMP endpoint
curl -I https://aps-workspaces.us-east-2.amazonaws.com/workspaces/<workspace-id>/api/v1/remote_write
```

### Issue: IAM Identity Center not enabled

**Cause**: AWS IAM Identity Center is not set up

**Solution:**
1. Go to AWS Console → IAM Identity Center
2. Click "Enable"
3. Set up the organization email
4. Add users
5. Grant Grafana permissions

## 💰 Cost Estimation

### AMP (AWS Managed Prometheus)
- Metric collection: $0.30 per million samples
- Metric storage: $0.03 per GB-month
- Queries: $0.01 per million samples
- **Estimated**: ~$10-30/month (depending on workload)

### AMG (AWS Managed Grafana)
- Workspace: $9/month per active user
- **Estimated**: $9-90/month (depending on the number of users)

### Total Estimated Cost
- **1-5 users**: ~$60-80/month
- **Compared to self-hosting**: Similar or slightly higher
- **Advantages**: Fully managed, auto-scaling, high availability

## 📚 Related Documentation

- [AWS Managed Prometheus](https://docs.aws.amazon.com/prometheus/)
- [AWS Managed Grafana](https://docs.aws.amazon.com/grafana/)
- [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/)
- [Prometheus Remote Write](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write)

## 🎯 Summary

### Automated Parts ✅
- AMP Workspace creation
- AMG Workspace creation
- AMP ↔ AMG data source connection
- ParallelCluster → AMP metric sending

### Manual Tasks Needed 🔧
- Enable IAM Identity Center (one-time)
- Add Grafana users (per user)
- Create dashboards (optional)

### Timeline
- Infrastructure deployment: ~10 minutes
- User addition: ~1 minute
- Cluster creation: ~30 minutes
- **Total**: ~40 minutes (mostly automated)
