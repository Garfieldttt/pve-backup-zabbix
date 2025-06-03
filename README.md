# Zabbix-Proxmox-Backup  
![Zabbix](https://img.shields.io/badge/Zabbix-6.0%2B-blue) ![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Notice  
This template is designed for use with the **Zabbix Agent (active)** and requires **Proxmox VE** with `vzdump`-based backup configuration.

---

# The `template_app_proxmox_backup` includes:

| Item                            | Description                                                  |
|---------------------------------|--------------------------------------------------------------|
| **backup.status**               | Backup success/failure status (0 = fail, 1 = success). + trigger      |
| **backup.starttime**            | Unix timestamp of the last backup start.                     |
| **backup.endtime**              | Unix timestamp of the last backup end.                       |
| **backup.starttime (text)**     | Converted start timestamp (human-readable).                  |
| **backup.endtime (text)**       | Converted end timestamp (human-readable).                    |
| **backup.duration** *(opt.)*    | Optional: backup runtime (in seconds or minutes).            |
| **backup.size**                 | Size of the backup (in bytes, MB, or GB).                    |

---

## Features

- VM discovery via Low-Level Discovery (LLD)
- Backup monitoring per VM based on `vzdump` logs or API
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

1. Import the XML template into **Zabbix**.
2. Assign the template to your **Proxmox VE host**.
3. Ensure the backup data (status, timestamps, size) is collected via agent or script.
4. Use preprocessing for timestamp conversion and size normalization (if needed).

---

## Usage

Use this template to monitor **Proxmox VE VM backups** via Zabbix.  
It helps detect failed jobs, long durations, missing templates, and unusual backup sizes.

---

## License  
MIT – use freely, contribute, adapt as needed.

---
