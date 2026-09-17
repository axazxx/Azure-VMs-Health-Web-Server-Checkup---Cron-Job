# Azure VMs Service Health Checker (Cron Job)

A small Bash script that automatically checks whether my Azure VMs are running, and whether the web server on each one (IIS or Nginx) is actually up, using cron.

## Description

I have 5 VMs running on Azure — 3 Windows VMs running IIS, and 2 Linux VMs running Nginx. Instead of manually logging into the Azure Portal every time to check their status, I can use this script which automatically checks and writes the results to a log file, so I or anyone monitoring the infra/environment can just check the log file to know the current state of everything. This Cron Job can also be scheduled to check in intervals.

## What it actually checks

For every VM, in order:
1. **Is the VM on/running** (via `az vm get-instance-view`)
2. **If it's on, is the web server actually running inside it**
   - Windows VMs → checks the `W3SVC` service (IIS internal service name)
   - Linux VMs → checks nginx `systemctl is-active nginx`

If the VM is off, it skips the service check entirely (no point checking a service on a machine that isn't running) and just logs the VM as down.

## Prerequisites

- An Azure subscription with VMs (on which you want to perform checkups) already created in the same resource group
- A separate "runner" VM to execute the cron job from (in my case, `cron-job-vm`)
- Azure CLI installed on that runner VM
- The runner VM logged in via `az login --identity`

## Setup

1. Clone this repo (or just copy `service_health_check.sh`) onto your runner VM.
2. Make it executable:
   ```bash
   chmod +x service_health_check.sh
   ```
3. Open the script and edit the variables to match your environment:
   ```bash
   RG="cron-job-vms"                              # your resource group name
   LOG_FILE="/home/azureuser/service_health.log"  # where to write the log
   WIN_VMS=("vm03" "vm04" "vm05")                 # your Windows VM names
   LIN_VMS=("vm01" "vm02")                        # your Linux VM names
   ```
5. Turn on Managed Identity for your runner vm in Identity section and provide role assignment to your runner vm as contributer.
6. Then Go to IAM of your resource-group which contains your vms that needs checkup and add role assignment → choose 'Virtual Machine Contributor' → under Members, select 'Managed identity' → pick your Runner vm → assign. Now your runner can access your environment VMs.
4. Run it once manually to confirm it works:
   ```bash
   ./service_health_check.sh
   cat service_health.log
   ```

### Scheduling it with cron

- If you wish to schedule this checkup;
On your runner vm:
```bash
crontab -e
```
Add a line (this example runs every 15 minutes):
```
*/15 * * * * /home/azureuser/service_health_check.sh
```

### How to show it works
**Run these commands on your runner vm**
**Power state check:**
```bash
# Stop a VM from the portal or CLI
az vm stop -g cron-job-vms -n vm01

# Run the script and check the log — should show:
# [ALERT] VM is NOT running

# Start it back up
az vm start -g cron-job-vms -n vm01
```

**Nginx check (Linux VMs):**
```bash
az vm run-command invoke -g cron-job-vms -n vm01 \
  --command-id RunShellScript --scripts "sudo systemctl stop nginx"

# Run the script — should show:
# [ALERT] VM Running | Nginx is DOWN

az vm run-command invoke -g cron-job-vms -n vm01 \
  --command-id RunShellScript --scripts "sudo systemctl start nginx"
```

**IIS check (Windows VMs):**
```bash
az vm run-command invoke -g cron-job-vms -n vm03 \
  --command-id RunPowerShellScript --scripts "Stop-Service W3SVC"

# Run the script — should show:
# [ALERT] VM Running | IIS is DOWN/STOPPED

az vm run-command invoke -g cron-job-vms -n vm03 \
  --command-id RunPowerShellScript --scripts "Start-Service W3SVC"
```

### Sample log output

```
==========================================================
[2026-09-17 11:14:52] Starting Health Check for 5 Azure VMs
[2026-09-17 11:14:52] vm-win-01 (Windows): [OK] VM Running | IIS (W3SVC) is RUNNING
[2026-09-17 11:14:52] vm-win-02 (Windows): [OK] VM Running | IIS (W3SVC) is RUNNING
[2026-09-17 11:14:52] vm-win-03 (Windows): [OK] VM Running | IIS (W3SVC) is RUNNING
[2026-09-17 11:14:52] vm-lin-01 (Linux):   [OK] VM Running | Nginx is RUNNING
[2026-09-17 11:14:52] vm-lin-02 (Linux):   [OK] VM Running | Nginx is RUNNING
[2026-09-17 11:14:52] Health check cycle complete.
```

## What I learned from this project

- **Exact-match vs. substring-match matters a lot in monitoring scripts.** A "close enough" text check can silently hide the exact failure you built the script to catch — `grep -q "active"` matching "inactive" was a good lesson in why loose string matching is dangerous.
- **Managed Identities are usually the better choice over Service Principals** for scripts running on Azure VMs — easy to create, no credentials to create.
- **Cron doesn't inherit your shell environment.** Things that work perfectly when you run a script by hand can fail in cron because of a missing `PATH`, a different user's login session, or a relative file path — I mentioned all three at different points.
- **Why Cron Jobs are Important** Cron Job make regular checkups of infra/environment very easy and less time consuming where you only need to check the log file to get your report.
- **Scheduling Cron Jobs** Learned how to schedule a script/cron job to be executed automatically at provided intervals of time.

## Blockers


1. **It read the VM's power state from a fixed array position** (`statuses[1]`), which isn't guaranteed to always be in that position. Fixed by filtering for the status whose `code` starts with `PowerState/` instead — that way it doesn't matter what order Azure returns things in.
2. **The Nginx check used a loose text search** (`grep -q "active"`) — and since the word `"inactive"` *contains* the substring `"active"`, a **stopped** Nginx service was being logged as running. Fixed by matching on the whole word only (`grep -qw "active"`).
3. I did not know the script cannot access the VMs path to run commands. Therefore i added a PATH with all the binaries so that it can execute commands.
4. **Couldn't create a Service Principal** — my Azure account didn't have permission to register apps in Entra ID. Switched to a **Managed Identity** on the cron VM instead, provided the vm with 'Virtual Machine Contributer' which allowed it to access the VMs.
5. I'd logged in with `az login --identity` as a 'root user' than the one cron would actually run the script as 'azureuser'. Azure CLI sessions are per-user, so `root` and `azureuser` don't share a login.

## Documents referred
- https://learn.microsoft.com/en-us/azure/virtual-machines/states-billing
- https://www.google.com/search?q=https://learn.microsoft.com/en-us/cli/azure/vm%3Fview%3Dazure-cli-latest%23az-vm-get-instance-view
- https://www.google.com/search?q=https://learn.microsoft.com/en-us/cli/azure/vm/run-command%3Fview%3Dazure-cli-latest%23az-vm-run-command-invoke
- https://learn.microsoft.com/en-us/azure/virtual-machines/windows/run-command
- https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command

## Possible future improvements

- Send an actual alert (email/Slack/webhook) instead of only writing to a log file
- Add log rotation (via `logrotate`) so the log file doesn't grow forever
- Generalize the script into a function instead of two near-duplicate loops, so adding a new VM type doesn't mean copy-pasting a whole block