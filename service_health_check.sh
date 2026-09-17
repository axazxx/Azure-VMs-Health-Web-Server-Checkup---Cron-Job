#!/bin/bash
#
#####################################################################
#
# Desc: This script allows you to check VMs(Win+Lin) active status aswell as IIS(Win-VMs) & Nginx(Lin-VMs) status
# Command: ./service_health_check.sh  ,  LogFile: service_health.log
# Author: Anas
# Date: 9/17/2026
# Version: 0.0.7v
####################################################################

# Ensure Azure CLI is discoverable by cron
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin"

RG="cron-job-vms"
LOG_FILE="/home/azureuser/service_health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# VMs Definitions
WIN_VMS=("vm03" "vm04" "vm05")
LIN_VMS=("vm01" "vm02")

echo "==========================================================" >> "$LOG_FILE"
echo "[$DATE] Starting Health Check for 5 Azure VMs" >> "$LOG_FILE"

# 1. Check Windows VMs & IIS/W3SVC status
for vm in "${WIN_VMS[@]}"; do

# Check VM Running status
    POWER=$(az vm get-instance-view -g "$RG" -n "$vm" \
        --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" \
        -o tsv )

    if [ "$POWER" != "VM running" ]; then
        echo "[$DATE] $vm (Windows): [ALERT] VM is NOT running (State: $POWER)" >> "$LOG_FILE"
        continue
    fi

# Query IIS service via PowerShell Run Command
    STATUS=$(az vm run-command invoke \
        --resource-group "$RG" \
        --name "$vm" \
        --command-id RunPowerShellScript \
        --scripts '(Get-Service -Name W3SVC).Status' \
        --query 'value[0].message' -o tsv )

# Output if-else for IIS
    if [ "$STATUS" == "Running" ]; then
        echo "[$DATE] $vm (Windows): [OK] VM Running | IIS (W3SVC) is RUNNING" >> "$LOG_FILE"
    else
        echo "[$DATE] $vm (Windows): [ALERT] VM Running | IIS is DOWN/STOPPED ($STATUS)" >> "$LOG_FILE"
    fi
done

# 2. Check Linux VMs & Nginx status
for vm in "${LIN_VMS[@]}"; do

# Check VM Running status
    POWER=$(az vm get-instance-view -g "$RG" -n "$vm" \
        --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" \
        -o tsv )

    if [ "$POWER" != "VM running" ]; then
        echo "[$DATE] $vm (Linux): [ALERT] VM is NOT running (State: $POWER)" >> "$LOG_FILE"
        continue
    fi

# Query Nginx service via Shell Run Command
    STATUS=$(az vm run-command invoke \
        --resource-group "$RG" \
        --name "$vm" \
        --command-id RunShellScript \
        --scripts 'systemctl is-active nginx' \
        --query 'value[0].message' -o tsv )

# Output if-else for nginx
    if echo "$STATUS" | grep -qw "active"; then
        echo "[$DATE] $vm (Linux):   [OK] VM Running | Nginx is RUNNING" >> "$LOG_FILE"
    else
        echo "[$DATE] $vm (Linux):   [ALERT] VM Running | Nginx is DOWN ($STATUS)" >> "$LOG_FILE"
    fi
done

echo "[$DATE] Health check cycle complete." >> "$LOG_FILE"