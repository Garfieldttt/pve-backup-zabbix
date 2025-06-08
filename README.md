# Zabbix-Proxmox-Backup  

## Notice  
This template is designed for use with the **Zabbix Agent (active)** and requires **Proxmox VE** with `vzdump`-based backup configuration.

---

# The `template_app_proxmox_backup` includes:

| Item                            | Description                                                  |
|---------------------------------|--------------------------------------------------------------|
| **backup.status**               | Backup success/failure status (0 = fail, 1 = success). + trigger      |
| **Trigger: No Recent Backup** | Fires if **no backup has occurred within the last 48 hours**. The time period is configurable via `{$BACKUP_TIME}`. |
| **backup.starttime**            | Unix timestamp of the last backup start.                     |
| **backup.endtime**              | Unix timestamp of the last backup end.                       |
| **backup.starttime (text)**     | Converted start timestamp (human-readable).                  |
| **backup.endtime (text)**       | Converted end timestamp (human-readable).                    |
| **backup.duration** *(opt.)*    | Optional: backup runtime (in seconds or minutes).            |
| **backup.size**                 | Size of the backup (in bytes, MB, or GB).                    |

---

## Features

- VM discovery via Low-Level Discovery (LLD)
- Backup monitoring per VM based on `vzdump` logs
- Timestamp conversion via preprocessing (to readable datetime)
- Backup size tracking
- Tagged items and triggers for filtering and automation
- Trigger prototypes for:
  - Failed backups

---

## Prerequisites

- **Proxmox VE** host with regular vzdump-based backups
- **Zabbix Agent (active)** installed and configured
- **Zabbix Server 7.0 or higher**

---

## Installation & Setup

1. Import the YAML template into **Zabbix**.
2. Assign the template to your **Proxmox VE host**.
3. Install required tools and deploy the vzdump hook script on your Proxmox host:
### 1. Ins temporäre Verzeichnis wechseln
#!/bin/bash

## 1. Change to the temporary directory
cd /tmp/

## 2. Clone the repository
git clone https://github.com/Garfieldttt/pve-backup-zabbix.git

## 3. Copy the script and make it executable
sudo cp pve-backup-zabbix/7.0/vzdump-hook-json.sh /usr/local/bin/vzdump-hook-json.sh
sudo chmod +x /usr/local/bin/vzdump-hook-json.sh

## 4. Open crontab and add the job (every 10 minutes)
crontab -e
## Then append this line:
*/10 * * * * /usr/local/bin/vzdump-hook-json.sh


---


## Usage

Use this template to monitor **Proxmox VE VM backups** via Zabbix.  
It helps detect failed jobs, long durations, missing templates, and unusual backup sizes.

---
