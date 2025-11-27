# Training Cluster GPU Reliability

## 1. Cluster Description
* 128 P5en instances 
* Purpose: Distributed training of MoE Model
    * UltraCluster with 1,024 GPUs on p5en.48xlarge (8 GPUs/instance → 128 instances).
    * Framework: Megatron-LM, pyxis/enroot container
    

## 2. The AWS EC2 Instance-Level SLA is 99.5% or higher per month. 

This means that "the ratio of Unavailability in a month is ≤ 0.5%". Converted to a daily average, the average allowable Unavailability per day is 7.2 minutes (= 1440 × 0.005).

Therefore, to meet 99.5% SLA:
* Daily failure count F vs MTTR: 
* If MTTR=60 minutes, F ≤ 0.12 failures/day
* If MTTR=30 minutes, F ≤ 0.24 failures/day
* If MTTR=10 minutes, F ≤ 0.72 failures/day
* If MTTR=5 minutes, F ≤ 1.44 failures/day
* If F=0.5 failures/day, MTTR=10 minutes ==> Uptime = 100 × (1 - 0.5 × 10/1440) ≈ 99.653% → SLA met

## 3. Recovery Solutions Based on GPU Failure Rate

### GPU Failure Rates(based on publicaly available data)
From the publicly available failure rate data, the Llama-3 405B 16k H100 cluster (2000 nodes, 1 node=8xH100) training logs from Meta, we can estimate the daily failure rate for 128 nodes (H200 is assumed to be 20% higher than the measured H100) as a worst case scenario.

Daily Failure Rate Estimate for P5en.48xlarge nodes (8x H200) and 128 nodes (1024 H200):
| Category | Raw Node Failure Rate (failures / node-day) | Daily Failures for 128-node (1024 GPU) Cluster (failures / 128-node-day) | MTTF(Mean Time To First Failure) | 근거 |
|----------|-------------------------------------------|---------------------------------------------------------------------|--------------------------------|------|
| A100 (RSC-1, Meta measured) | 0.0065 | 0.83 failures/day | 29 h | arXiv (Meta) |
| H100 (Meta measured) | 0.0038 | 0.49 failures/day | 49 h | arXiv The Llama 3 Herd of Models. 3.3.4 Reliability and Operational Challenges (Meta) |
| H200 (H100 × 1.2 conservative) | 0.0045 | 0.58 failures/day | 42 h | H100 measured × 1.2 |

### Maximizing Resource Utilization for 128x P5en.48xlarge
The failure rate F below refers to the average daily failure count for the 128-instance (1024xH200) cluster.

ETTR (Effective Training Time Ratio): The ratio of the actual training time to the total time the CB instance is allocated.

ETTR = 1 - (Planned pause (S/T) + Expected failure loss (F × (T/2 + R)/1440))

Where:
* T (Checkpoint interval, minutes): 240 (4 hours)
* S (Checkpoint Save time, minutes): 1
* R (Recovery time, minutes) — Slurm re-launch: 30
* F (Failures per day per 128-instance)
* 1440 = minutes/day = 60x24

### Comparison of Resource Utilization for 128-node (1 node = 8x H200) with and without Spares
Below a failure rate of 0.4, having no spares is more advantageous, and the utilization difference is marginal even at a failure rate of 0.5.

Comparing the case of:
* 30-minute Recovery time without spare nodes (128-node)
* Using a warm spare (127 active + 1 spare node) with Recovery times of 5 and 2 minutes:

No spares (all 128 running): 30 minutes of downtime per failure
ETTR = 1 - S/T - F(T/2 + R)/1440

Warm spare (127+1): Normally 127/128 (=0.9921875) runs, 5 and 2 minutes of downtime during replacement respectively.
ETTR = 127/128 × (S/T - F(T/2 + R)/1440)

Here R = 5 minutes or 2 minutes (warm spare)
Checkpoint interval 4 hours, T = 240 minutes

