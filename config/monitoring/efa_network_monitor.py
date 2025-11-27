#!/usr/bin/env python3
"""
EFA Network Performance Monitor
Collects EFA network statistics and sends to CloudWatch
"""

import boto3
import time
import subprocess
import os
from datetime import datetime

# Configuration
NAMESPACE = 'ParallelCluster/Network'
COLLECTION_INTERVAL = 60  # seconds
BATCH_SIZE = 5  # 5 minutes of data before sending

cloudwatch = boto3.client('cloudwatch')

def get_instance_id():
    """Get EC2 instance ID"""
    try:
        result = subprocess.run(
            ['ec2-metadata', '--instance-id'],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.stdout.split()[-1].strip()
    except Exception as e:
        print(f"Error getting instance ID: {e}")
        return "unknown"

def get_efa_interfaces():
    """Get list of EFA interfaces"""
    try:
        interfaces = []
        ib_path = '/sys/class/infiniband'
        if os.path.exists(ib_path):
            interfaces = [d for d in os.listdir(ib_path) if os.path.isdir(os.path.join(ib_path, d))]
        return interfaces
    except Exception as e:
        print(f"Error listing EFA interfaces: {e}")
        return []

def collect_efa_stats(interface):
    """Collect EFA statistics (lightweight operation)"""
    stats = {}
    base_path = f'/sys/class/infiniband/{interface}/ports/1/counters'
    
    try:
        # Receive data
        with open(f'{base_path}/port_rcv_data', 'r') as f:
            stats['rx_bytes'] = int(f.read().strip()) * 4  # 4 bytes per unit
        
        # Transmit data
        with open(f'{base_path}/port_xmit_data', 'r') as f:
            stats['tx_bytes'] = int(f.read().strip()) * 4
        
        # Packets
        with open(f'{base_path}/port_rcv_packets', 'r') as f:
            stats['rx_packets'] = int(f.read().strip())
        
        with open(f'{base_path}/port_xmit_packets', 'r') as f:
            stats['tx_packets'] = int(f.read().strip())
        
        # Errors
        with open(f'{base_path}/port_rcv_errors', 'r') as f:
            stats['rx_errors'] = int(f.read().strip())
        
        with open(f'{base_path}/port_xmit_discards', 'r') as f:
            stats['tx_discards'] = int(f.read().strip())
        
    except Exception as e:
        print(f"Error collecting stats for {interface}: {e}")
        return None
    
    return stats

def calculate_rates(current, previous, time_delta):
    """Calculate rates (bytes/sec, packets/sec)"""
    if not previous or time_delta == 0:
        return None
    
    rates = {}
    for key in ['rx_bytes', 'tx_bytes', 'rx_packets', 'tx_packets']:
        if key in current and key in previous:
            # Check if counter was reset
            if current[key] >= previous[key]:
                rates[key + '_rate'] = (current[key] - previous[key]) / time_delta
            else:
                # Counter overflow - ignore
                rates[key + '_rate'] = 0
    
    # Error rates
    rates['rx_errors'] = current.get('rx_errors', 0)
    rates['tx_discards'] = current.get('tx_discards', 0)
    
    return rates

def send_metrics_to_cloudwatch(metrics_buffer, instance_id):
    """Send metrics to CloudWatch in batches"""
    if not metrics_buffer:
        return
    
    metric_data = []
    
    for timestamp, interface, metrics in metrics_buffer:
        for metric_name, value in metrics.items():
            # Determine unit
            if 'bytes_rate' in metric_name:
                unit = 'Bytes/Second'
            elif 'packets_rate' in metric_name:
                unit = 'Count/Second'
            else:
                unit = 'Count'
            
            metric_data.append({
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Timestamp': timestamp,
                'Dimensions': [
                    {'Name': 'InstanceId', 'Value': instance_id},
                    {'Name': 'Interface', 'Value': interface}
                ]
            })
    
    # CloudWatch allows max 20 metrics per call
    try:
        for i in range(0, len(metric_data), 20):
            batch = metric_data[i:i+20]
            cloudwatch.put_metric_data(
                Namespace=NAMESPACE,
                MetricData=batch
            )
            print(f"Sent {len(batch)} metrics to CloudWatch")
    except Exception as e:
        print(f"Error sending metrics to CloudWatch: {e}")

def main():
    print("Starting EFA Network Monitor...")
    
    instance_id = get_instance_id()
    print(f"Instance ID: {instance_id}")
    
    interfaces = get_efa_interfaces()
    if not interfaces:
        print("No EFA interfaces found. Exiting.")
        return
    
    print(f"Found EFA interfaces: {interfaces}")
    
    # Store previous statistics
    previous_stats = {iface: None for iface in interfaces}
    previous_time = time.time()
    
    # Batch buffer
    metrics_buffer = []
    
    while True:
        try:
            current_time = time.time()
            time_delta = current_time - previous_time
            
            for interface in interfaces:
                # Collect statistics (< 1ms)
                current_stats = collect_efa_stats(interface)
                
                if current_stats:
                    # Calculate rates
                    rates = calculate_rates(
                        current_stats,
                        previous_stats[interface],
                        time_delta
                    )
                    
                    if rates:
                        # Add to buffer
                        metrics_buffer.append((
                            datetime.utcnow(),
                            interface,
                            rates
                        ))
                        
                        # Local log
                        rx_mbps = rates.get('rx_bytes_rate', 0) * 8 / 1_000_000
                        tx_mbps = rates.get('tx_bytes_rate', 0) * 8 / 1_000_000
                        print(f"{interface}: RX={rx_mbps:.2f} Mbps, TX={tx_mbps:.2f} Mbps")
                    
                    previous_stats[interface] = current_stats
            
            previous_time = current_time
            
            # Send batch (every 5 minutes)
            if len(metrics_buffer) >= BATCH_SIZE * len(interfaces):
                send_metrics_to_cloudwatch(metrics_buffer, instance_id)
                metrics_buffer = []
            
            time.sleep(COLLECTION_INTERVAL)
            
        except KeyboardInterrupt:
            print("\nShutting down...")
            # Send remaining metrics
            if metrics_buffer:
                send_metrics_to_cloudwatch(metrics_buffer, instance_id)
            break
        except Exception as e:
            print(f"Error in main loop: {e}")
            time.sleep(COLLECTION_INTERVAL)

if __name__ == '__main__':
    main()
