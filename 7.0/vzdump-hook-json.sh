#!/bin/bash

LOG_DIR="/var/log/vzdump"
OUT_FILE="/var/log/backups.log"
NODE="pve"

echo '{ "backups": [' > "$OUT_FILE"
first=1

for logfile in "$LOG_DIR"/*.log; do
    [[ ! -s "$logfile" ]] && continue

    vmid=$(basename "$logfile" | grep -oE '[0-9]+')
    name="null"
    storage="null"
    size_bytes=0
    start=$(stat -c %Y "$logfile")
    end=$start

    status="UNKNOWN"
    error_found=0
    finished_found=0
    started_found=0

    while IFS= read -r line; do
        [[ "$line" == *"Starting Backup"* ]] && started_found=1
        [[ "$line" == *"Finished Backup"* ]] && finished_found=1
        [[ "$line" == *"ERROR:"* ]] && error_found=1

        if [[ "$line" =~ VM\ Name:\ (.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
        fi

        if [[ "$line" =~ CT\ Name:\ (.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
        fi

        if [[ "$line" =~ include\ disk ]]; then
            match=$(echo "$line" | grep -oP "'[^']+:[^']+'" | head -n1 | cut -d':' -f1 | tr -d "'")
            [[ -n "$match" ]] && storage="$match"
        fi
    done < "$logfile"

    if [[ "$error_found" -eq 1 ]]; then
        status="FAILED"
    elif [[ "$finished_found" -eq 1 ]]; then
        status="OK"
    elif [[ "$started_found" -eq 1 ]]; then
        status="RUNNING"
    fi

    # JSON quoting, wenn nötig
    [[ "$name" != "null" ]] && name="\"$name\""
    [[ "$storage" != "null" ]] && storage="\"$storage\""

    [[ $first -eq 0 ]] && echo "," >> "$OUT_FILE"
    first=0

    cat >> "$OUT_FILE" <<EOF
  {
    "vmid": "$vmid",
    "name": $name,
    "node": "$NODE",
    "start": $start,
    "end": $end,
    "status": "$status",
    "storage": $storage,
    "size_bytes": $size_bytes
  }
EOF

done

echo "] }" >> "$OUT_FILE"
