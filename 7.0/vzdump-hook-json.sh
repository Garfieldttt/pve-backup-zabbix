#!/bin/bash

LOG_DIR="/var/log/vzdump"
OUTPUT="/var/log/backups.log"
NODE="pve"

echo '{ "backups": [' > "$OUTPUT"

first_entry=true

for logfile in "$LOG_DIR"/*.log; do
    [ -e "$logfile" ] || continue

    vmid=$(basename "$logfile" | cut -d'-' -f2 | cut -d'.' -f1)
    name=$(grep -m1 "VM Name:" "$logfile" | sed -E 's/.*VM Name:\s*//')
    [[ -z "$name" ]] && name=null

    start=$(grep -m1 "Starting Backup" "$logfile" | cut -d' ' -f1-2)
    end=$(grep -m1 "Finished Backup" "$logfile" | cut -d' ' -f1-2)
    [[ -z "$end" ]] && end=$(date '+%F %T')

    start_ts=$(date -d "$start" +%s 2>/dev/null || echo 0)
    end_ts=$(date -d "$end" +%s 2>/dev/null || echo "$start_ts")

    status="FAILED"
    grep -q "Finished Backup" "$logfile" && status="OK"
    grep -q "status = running" "$logfile" && status="running"

    size_bytes=$(grep -i "transferred" "$logfile" | grep -Eo '[0-9.]+ GiB' | awk '{printf "%.0f\n", $1 * 1024 * 1024 * 1024}' | tail -n1)
    [[ -z "$size_bytes" ]] && size_bytes=0

    $first_entry || echo "," >> "$OUTPUT"
    first_entry=false

    cat <<EOF >> "$OUTPUT"
    {
      "vmid": "$vmid",
      "name": ${name:+\"$name\"},
      "node": "$NODE",
      "start": $start_ts,
      "end": $end_ts,
      "status": "$status",
      "size_bytes": $size_bytes
    }
EOF

done

echo "] }" >> "$OUTPUT"
