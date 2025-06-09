
# Zabbix Integration: Proxmox VE Backup Monitoring

**Template:** `Template Proxmox VE Backup`  
**Zabbix Version:** 7.0+  
---

## 💡 Overview

Agentless monitoring of Proxmox VE backup jobs:
- Reads JSON log files (e.g., `/var/log/backups.log`)
- Detects VMs via Low-Level-Discovery
- Extracts backup start/end times, size & status
- Triggers if a backup is missing or fails

---

## 🔍 Requirements

- Proxmox VE generates a JSON-format backup log  
- Backup log is accessible by Zabbix server or proxy  
- Template is applied to the host that can read the log file

---

## ⚙️ Macros

| Macro                 | Default Value                | Description                                         |
|-----------------------|------------------------------|-----------------------------------------------------|
| `{$BACKUP_LOCATION}`  | `/var/log/backups.log`       | Path to the JSON backup log                        |
| `{$BACKUP_TIME}`      | `48h`                        | Time threshold to trigger alert on missing backup  |
| `{$TRIGGER_BACKUP_FAILED}`      | `1`                        | Enable/Disable the 'Backup failed on(VMID: {#VMID}' trigger with macro  |
| `{$TRIGGER_NOBACKUP}`      | `1`                        | Enable/Disable the 'No backup in {$BACKUP_TIME} (VMID: {#VMID})' trigger with macro  |

---

## 📦 Value Maps

**Name:** `BACKUP-STATUS`

| Value | Meaning  |
|-------|----------|
| 1     | OK       |
| 0     | ERROR    |
| 2     | RUNNING  |

---

## 📦 Items

### Active Items

- **raw.data.pve_backup**  
  Key: `vfs.file.contents[{$BACKUP_LOCATION}]`  
  Type: *ZABBIX_ACTIVE*  
  Purpose: Reads the full JSON log file

### Dependent Items (via LLD)

- `backup.starttime[{#VMID}]` – Backup start time  
- `backup.endtime[{#VMID}]` – Backup end time  
- `backup.size[{#VMID}]` – Backup size in bytes  
- `backup.status[{#VMID}]` – 0/1/2 as status code  

All values are extracted using JSONPath and preprocessing from the master item `vfs.file.contents[...]`.

---

## 🔔 Triggers

- **No backup in `{$BACKUP_TIME}` (VMID: {#VMID})**  
  Condition: `nodata(/…/backup.endtime[{#VMID}],{$BACKUP_TIME})=1`  
  → No backup within the specified time frame

- **Backup failed on (VMID: {#VMID})**  
  Condition: `last(...backup.status[{#VMID}])=0`  
  → Backup status indicates failure

Both triggers are set to **HIGH** priority.

---

## 🔧 Customization & Operation

- Adjust `{$BACKUP_LOCATION}` & `{$BACKUP_TIME}` to match your setup  
- Ensure JSON formatting is correct  
- Consider log rotation and file size (e.g., set `max_lines`)  
- Extend with more items/templates if needed

---

## ✅ Conclusion

A compact and effective template for monitoring Proxmox VE backups.  
Uses modern Zabbix features like active items, preprocessing, LLD, and dependent items – ideal for integration into your infrastructure.

---

