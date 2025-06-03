#!/bin/bash
#
# /usr/local/bin/vzdump-hook-json.sh
#
# Proxmox-Hook für LXC & QEMU (auch bei Bulk-Jobs), der:
# 1. beim Backup-Start die Startzeit in /tmp/vzdump-<VMID>.start ablegt
# 2. bei jedem VM/CT-Ende (LXC: backup-end  QEMU: post-stop) bzw. bei job-end (Fallback)
#    pro VM eine Datei /var/log/backups.d/<VMID>.json anlegt mit:
#      vmid, name, node, start, end, status, storage, size_bytes
# 3. anschließend aus **allen** /var/log/backups.d/*.json
#    eine Gesamtdatei /var/log/backups.log zusammenbaut.

LOGDIR="/var/log/backups.d"            
LOGFILE="/var/log/backups.log"         
LOCKFILE="/var/lock/vzdump-hook-json.lock"
STARTDIR="/tmp"

ACTION="$1"       # backup-start | backup-end (LXC)  oder  pre-start | post-stop (QEMU) | job-end
RAW1="$2"         # QEMU: VMID, LXC: "snapshot", job-end: leer
RAW2="$3"         # QEMU: Modus,    LXC: CTID,      job-end: leer
BACKUPFILE="$4"   # QEMU: Pfad zur Backup-Datei, LXC/PBS: leer
EXITCODE="$5"     # nur bei backup-end/post-stop gesetzt

NODE="$(hostname -s)"
NOW="$(date +%s)"

# ──────────────────────────────────────────────────────────────────────────────
# 0) Verzeichnisse/Rechte sicherstellen
# ──────────────────────────────────────────────────────────────────────────────
mkdir -p "$LOGDIR"
chown root:root "$LOGDIR"
chmod 755 "$LOGDIR"
mkdir -p /var/lock
chown root:root /var/lock
chmod 755 /var/lock
touch "$LOGFILE"
chown root:root "$LOGFILE"
chmod 644 "$LOGFILE"

# ──────────────────────────────────────────────────────────────────────────────
# Hilfsfunktion: JSON für eine VM-ID schreiben
# ──────────────────────────────────────────────────────────────────────────────
create_json() {
  local VMID="$1"; shift
  local STARTTIME="$1"; shift
  local ENDTIME="$1"; shift
  local STATUS="$1"; shift
  local STORAGE="$1"; shift
  local SIZE_BYTES="$1"; shift

  local VMNAME ESC_NAME
  if [[ "$VMID" =~ ^[0-9]+$ ]]; then
    if [ -f "/etc/pve/lxc/${VMID}.conf" ]; then
      VMNAME="$(grep -m1 -E '^hostname:' "/etc/pve/lxc/${VMID}.conf" | cut -d' ' -f2- | tr -d '\r\n')"
    elif [ -f "/etc/pve/qemu-server/${VMID}.conf" ]; then
      VMNAME="$(grep -m1 -E '^name:' "/etc/pve/qemu-server/${VMID}.conf" | cut -d' ' -f2- | tr -d '\r\n')"
    else
      VMNAME="unbekannt"
    fi
  else
    VMNAME="unbekannt"
  fi

  ESC_NAME="$(printf '%s' "$VMNAME" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  local OUTFILE="${LOGDIR}/${VMID}.json"

  {
    printf '{'
    printf '"vmid":"%s",'   "$VMID"
    printf '"name":"%s",'    "$ESC_NAME"
    printf '"node":"%s",'    "$NODE"
    printf '"start":%d,'     "$STARTTIME"
    printf '"end":%d,'       "$ENDTIME"
    printf '"status":"%s",'  "$STATUS"
    printf '"storage":"%s",' "$STORAGE"
    printf '"size_bytes":%d' "$SIZE_BYTES"
    printf '}'
  } > "$OUTFILE"
}

# ──────────────────────────────────────────────────────────────────────────────
# 1) Beim Backup-Start nur Startzeit speichern und beenden
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "backup-start" || "$ACTION" == "pre-start" ]]; then
  if [[ "$RAW1" =~ ^[0-9]+$ ]]; then
    VMID="$RAW1"
  elif [[ "$RAW2" =~ ^[0-9]+$ ]]; then
    VMID="$RAW2"
  else
    exit 0
  fi
  echo "$NOW" > "${STARTDIR}/vzdump-${VMID}.start"
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2) Nur VM-End-Events verarbeiten: backup-end, post-stop, job-end
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" != "backup-end" && "$ACTION" != "post-stop" && "$ACTION" != "job-end" ]]; then
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3) Fallback bei job-end: alle verbliebenen Start-Files abschließen
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "job-end" ]]; then
  for startfile in "${STARTDIR}"/vzdump-*.start; do
    [[ ! -f "$startfile" ]] && continue
    VMID="$(basename "$startfile" | sed -e 's/^vzdump-//' -e 's/\.start$//')"
    STARTTIME="$(head -n1 "$startfile")"
    rm -f "$startfile"
    ENDTIME="$NOW"
    create_json "$VMID" "$STARTTIME" "$ENDTIME" "OK" "unbekannt" 0
  done
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4) VMID/CTID ermitteln (bei backup-end oder post-stop)
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$RAW1" =~ ^[0-9]+$ ]]; then
  VMID="$RAW1"
elif [[ "$RAW2" =~ ^[0-9]+$ ]]; then
  VMID="$RAW2"
else
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5) Startzeit abholen (falls vorhanden), sonst NOW
# ──────────────────────────────────────────────────────────────────────────────
if [[ -f "${STARTDIR}/vzdump-${VMID}.start" ]]; then
  STARTTIME="$(head -n1 "${STARTDIR}/vzdump-${VMID}.start")"
  rm -f "${STARTDIR}/vzdump-${VMID}.start"
else
  STARTTIME="$NOW"
fi
ENDTIME="$NOW"

# ──────────────────────────────────────────────────────────────────────────────
# 6) Status ermitteln (EXITCODE: 0 → OK, sonst ERR)
# ──────────────────────────────────────────────────────────────────────────────
if [[ -z "$EXITCODE" || "$EXITCODE" -eq 0 ]]; then
  STATUS="OK"
else
  STATUS="ERR"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 7) Storage ermitteln (grep "--storage <ID>" in Parent-PIDs)
# ──────────────────────────────────────────────────────────────────────────────
find_storage() {
  local pid="$1"
  while [ "$pid" != "1" ]; do
    if [ -r "/proc/$pid/cmdline" ]; then
      local cmd="$(tr '\0' ' ' < /proc/$pid/cmdline)"
      if [[ $cmd =~ --storage[[:space:]]+([^[:space:]]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
      fi
    fi
    pid="$(awk '/^PPid:/ {print $2}' /proc/$pid/status 2>/dev/null || echo "1")"
  done
  echo "unbekannt"
}
STORAGE="$(find_storage "$PPID")"

# ──────────────────────────────────────────────────────────────────────────────
# 8) size_bytes ermitteln
#    • QEMU: BACKUPFILE (Archiv) existiert → stat liefert exakte Bytes
#    • LXC/PBS: kein BACKUPFILE → fallback mit du auf /mnt/vzsnap0
#    • sonst 0
# ──────────────────────────────────────────────────────────────────────────────
if [[ -n "$BACKUPFILE" ]]; then
  if [[ "$BACKUPFILE" = /* ]]; then
    FULLPATH="$BACKUPFILE"
  else
    FULLPATH="/mnt/${BACKUPFILE}"
  fi
  if [ -f "$FULLPATH" ]; then
    SIZE_BYTES="$(stat --printf='%s' "$FULLPATH")"
  else
    SIZE_BYTES=0
  fi
else
  if [ -d "/mnt/vzsnap0" ]; then
    SIZE_BYTES="$(du -sb /mnt/vzsnap0 2>/dev/null | cut -f1)"
  else
    SIZE_BYTES=0
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 9) Einzel-JSON für diese VMID erzeugen → /var/log/backups.d/<VMID>.json
# ──────────────────────────────────────────────────────────────────────────────
create_json "$VMID" "$STARTTIME" "$ENDTIME" "$STATUS" "$STORAGE" "$SIZE_BYTES"

# ──────────────────────────────────────────────────────────────────────────────
# 10) Gesamt-JSON neu aus allen /var/log/backups.d/*.json zusammenbauen
#     → per flock, damit mehrere parallele Hooks nicht kollidieren
# ──────────────────────────────────────────────────────────────────────────────
(
  flock -x 200

  TMPFILE="$(mktemp)"
  echo -n '{ "backups": [' > "$TMPFILE"
  first=1

  for f in "$LOGDIR"/*.json; do
    [[ ! -f "$f" ]] && continue
    if [[ $first -eq 1 ]]; then
      first=0
    else
      echo -n ',' >> "$TMPFILE"
    fi
    cat "$f" >> "$TMPFILE"
  done

  echo '] }' >> "$TMPFILE"
  mv "$TMPFILE" "$LOGFILE"
  chown root:root "$LOGFILE"
  chmod 644 "$LOGFILE"

) 200> "$LOCKFILE"

exit 0
