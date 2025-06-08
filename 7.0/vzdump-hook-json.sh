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
    [[ -z "$name" ]] && name=null || name="\"$name\""

    start_line=$(grep -m1 "Starting Backup" "$logfile")
    end_line=$(grep -m1 "Finished Backup" "$logfile")

    start=$(echo "$start_line" | cut -d' ' -f1-2)
    end=$(echo "$end_line" | cut -d' ' -f1-2)

    start_ts=$(date -d "$start" +%s 2>/dev/null || echo 0)
    end_ts=$(date -d "$end" +%s 2>/dev/null || echo "$start_ts")

    # Status: Priorität: OK > running > FAILED
    if grep -q "Finished Backup" "$logfile"; then
        status="OK"
    elif grep -q "Starting Backup" "$logfile"; then
        status="running"
    else
        status="FAILED"
    fi

    # Größe extrahieren (z.B. "transferred 45.00 GiB")
    size_bytes=$(grep -i "transferred" "$logfile" | grep -Eo '[0-9.]+ GiB' | awk '{printf "%.0f", $1 * 1073741824}' | tail -n1)
    [[ -z "$size_bytes" ]] && size_bytes=0

    $first_entry || echo "," >> "$OUTPUT"
    first_entry=false

    cat <<EOF >> "$OUTPUT"
    {
      "vmid": "$vmid",
      "name": $name,
      "node": "$NODE",
      "start": $start_ts,
      "end": $end_ts,
      "status": "$status",
      "size_bytes": $size_bytes
    }
EOF

done

echo "] }" >> "$OUTPUT"
