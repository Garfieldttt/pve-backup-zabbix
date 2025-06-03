#!/bin/bash
LOGDIR="/var/log/backups.d"            # Per-VM JSON files
LOGFILE="/var/log/backups.log"         # Aggregated JSON
LOCKFILE="/var/lock/vzdump-hook-json.lock"
STARTDIR="/tmp"

ACTION="$1"       # backup-start | backup-end (LXC)  or  pre-start | post-stop (QEMU) | job-end
RAW1="$2"         # QEMU: VMID, LXC: "snapshot", job-end: empty
RAW2="$3"         # QEMU: mode,  LXC: CTID,       job-end: empty
BACKUPFILE="$4"   # QEMU: path to backup file, LXC/PBS: empty
EXITCODE="$5"     # only set during backup-end/post-stop

NODE="$(hostname -s)"
NOW="$(date +%s)"

# ──────────────────────────────────────────────────────────────────────────────
# 0) Ensure required directories and permissions
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
# 1) On backup start, save the timestamp and exit
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "backup-start" || "$ACTION" == "pre-start" ]]; then
  if [[ "$RAW1" =~ ^[0-9]+$ ]]; then
    VMID="$RAW1"
  elif [[ "$RAW2" =~ ^[0-9]+$ ]]; then
    VMID="$RAW2"
  else
    exit 0
  fi
  # Write start time to /tmp/vzdump-<VMID>.start
  echo "$NOW" > "${STARTDIR}/vzdump-${VMID}.start"
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2) Only process end events:
#       • LXC:   ACTION == backup-end
#       • QEMU:  ACTION == post-stop
#       • job-end: fallback in case individual VM hooks didn’t fire
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" != "backup-end" && "$ACTION" != "post-stop" && "$ACTION" != "job-end" ]]; then
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3) Determine VMID/CTID (or use "host" as fallback)
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$RAW1" =~ ^[0-9]+$ ]]; then
  VMID="$RAW1"
elif [[ "$RAW2" =~ ^[0-9]+$ ]]; then
  VMID="$RAW2"
else
  # If job-end with no RAW1/RAW2, optionally read the latest .start file
  # Here we just use "host" as a placeholder
  VMID="host"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4) Read start time (from file if available), else use NOW
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$VMID" != "host" && -f "${STARTDIR}/vzdump-${VMID}.start" ]]; then
  STARTTIME="$(head -n1 "${STARTDIR}/vzdump-${VMID}.start")"
  rm -f "${STARTDIR}/vzdump-${VMID}.start"
else
  STARTTIME="$NOW"
fi
ENDTIME="$NOW"

# ──────────────────────────────────────────────────────────────────────────────
# 5) Determine VM/CT name (host fallback uses $NODE)
# ──────────────────────────────────────────────────────────────────────────────
get_vm_name() {
  local id="$1"
  if [[ "$id" == "host" ]]; then
    echo "$NODE"
    return
  fi
  # LXC
  if [ -f "/etc/pve/lxc/${id}.conf" ]; then
    grep -m1 -E '^hostname:' "/etc/pve/lxc/${id}.conf" \
      | cut -d' ' -f2- | tr -d '\r\n'
    return
  fi
  # QEMU
  if [ -f "/etc/pve/qemu-server/${id}.conf" ]; then
    grep -m1 -E '^name:' "/etc/pve/qemu-server/${id}.conf" \
      | cut -d' ' -f2- | tr -d '\r\n'
    return
  fi
  echo "unknown"
}
VMNAME="$(get_vm_name "$VMID")"

# ──────────────────────────────────────────────────────────────────────────────
# 6) Determine backup status (OK or ERR)
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$VMID" == "host" ]]; then
  STATUS="OK"
else
  if [[ -z "$EXITCODE" || "$EXITCODE" -eq 0 ]]; then
    STATUS="OK"
  else
    STATUS="ERR"
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 7) Determine storage by walking parent PIDs and parsing "--storage"
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
  echo "unknown"
}
STORAGE="$(find_storage "$PPID")"

# ──────────────────────────────────────────────────────────────────────────────
# 8) Determine backup size (in bytes)
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$VMID" == "host" ]]; then
  SIZE_BYTES=0
elif [[ -n "$BACKUPFILE" ]]; then
  # QEMU backup: local or mounted archive file
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
  # LXC/PBS: estimate from /mnt/vzsnap0 if available
  if [ -d "/mnt/vzsnap0" ]; then
    SIZE_BYTES="$(du -sb /mnt/vzsnap0 2>/dev/null | cut -f1)"
  else
    SIZE_BYTES=0
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 9) Create per-VM JSON → /var/log/backups.d/<VMID>.json
# ──────────────────────────────────────────────────────────────────────────────
OUTFILE="${LOGDIR}/${VMID}.json"
ESC_NAME="$(printf '%s' "$VMNAME" | sed 's/\\/\\\\/g; s/"/\\"/g')"

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

# ──────────────────────────────────────────────────────────────────────────────
# 10) Rebuild the aggregate JSON using flock to avoid race conditions
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

cat /var/log/backups.log | jq > /var/log/pve-backup.json
exit 0

