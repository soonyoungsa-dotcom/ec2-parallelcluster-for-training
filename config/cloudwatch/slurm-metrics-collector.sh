#!/bin/bash
# ==============================================================================
# Slurm Metrics Collector for CloudWatch
# ==============================================================================
# Purpose: Collect Slurm queue and job metrics and send to CloudWatch
# Installation: Run on HeadNode via cron (every 1 minute)
# ==============================================================================

CLUSTER_NAME="${1:-p5en-48xlarge-cluster}"
AWS_REGION="${2:-us-east-2}"
NAMESPACE="ParallelCluster/${CLUSTER_NAME}/Slurm"

# Get Slurm queue statistics
NODES_TOTAL=$(sinfo -h -o "%D" | awk '{sum+=$1} END {print sum}')
NODES_IDLE=$(sinfo -h -t idle -o "%D" | awk '{sum+=$1} END {print sum}')
NODES_ALLOCATED=$(sinfo -h -t allocated,mixed -o "%D" | awk '{sum+=$1} END {print sum}')
NODES_DOWN=$(sinfo -h -t down,drain,draining -o "%D" | awk '{sum+=$1} END {print sum}')

# Get job statistics
JOBS_RUNNING=$(squeue -h -t RUNNING | wc -l)
JOBS_PENDING=$(squeue -h -t PENDING | wc -l)
JOBS_TOTAL=$(squeue -h | wc -l)

# Send metrics to CloudWatch
aws cloudwatch put-metric-data \
    --region ${AWS_REGION} \
    --namespace "${NAMESPACE}" \
    --metric-data \
        MetricName=NodesTotal,Value=${NODES_TOTAL:-0},Unit=Count \
        MetricName=NodesIdle,Value=${NODES_IDLE:-0},Unit=Count \
        MetricName=NodesAllocated,Value=${NODES_ALLOCATED:-0},Unit=Count \
        MetricName=NodesDown,Value=${NODES_DOWN:-0},Unit=Count \
        MetricName=JobsRunning,Value=${JOBS_RUNNING:-0},Unit=Count \
        MetricName=JobsPending,Value=${JOBS_PENDING:-0},Unit=Count \
        MetricName=JobsTotal,Value=${JOBS_TOTAL:-0},Unit=Count

# Log to syslog
logger -t slurm-metrics "Nodes: ${NODES_TOTAL} total, ${NODES_IDLE} idle, ${NODES_ALLOCATED} allocated, ${NODES_DOWN} down | Jobs: ${JOBS_RUNNING} running, ${JOBS_PENDING} pending"
