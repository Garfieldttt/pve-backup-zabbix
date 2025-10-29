#!/bin/bash

LOG_DIR="/var/log/vzdump"
OUTPUT="/var/log/backups.log"
NONBACKUPLOG="/var/log/nonbackups.log"
NODE="pve"

echo '{ "backups": [' > "$OUTPUT"

first_entry=true

for logfile in "$LOG_DIR"/*.log; do
    [ -e "$logfile" ] || continue
    
    #initializing variables
    start_ts=0
    end_ts=0
    duration=0
    size_bytes=0
    
    # VM ID from filename
    vmid=$(basename "$logfile" | cut -d'-' -f2 | cut -d'.' -f1)

    # VM Name
    name=$(grep -m1 "VM Name:" "$logfile" | sed -E 's/.*VM Name:\s*//')
    [[ -z "$name" ]] && name=null || name="\"$name\""

    # Timestamp lines
    start_line=$(grep -m1 "Starting Backup" "$logfile")
    end_line=$(grep -m1 "Finished Backup" "$logfile")

    start=$(echo "$start_line" | cut -d' ' -f1-2)
    end=$(echo "$end_line" | cut -d' ' -f1-2)

    start_ts=$(date -d "$start" +%s 2>/dev/null || echo 0)
    end_ts=$(date -d "$end" +%s 2>/dev/null || echo "$start_ts")

    let "duration = $end_ts - $start_ts"

    # Detect errors
    error_line=$(grep -E "ERROR:" "$logfile" | tail -n1 | sed -E 's/.*ERROR:\s*//')
    if [[ -n "$error_line" ]]; then
        error_json="\"$error_line\""
        status="FAILED"
    else
        error_json=null
        # Status priority: OK > running > FAILED
        if grep -q "Finished Backup" "$logfile"; then
            status="OK"
        elif grep -q "Starting Backup" "$logfile"; then
            status="running"
        else
            status="FAILED"
        fi
    fi

    size=$(grep -i "transferred" "$logfile" | grep -oP 'transferred \K[0-9.]+' | awk '{printf "%.0f", $1 }' | tail -n1)
    [[ -z "$size" ]] && size=0

    size_suffix=$(grep -oP 'transferred [0-9.]+ \K[KMG]iB' "$logfile")
    [[ -z "$size_suffix" ]] && size_suffix="NoN"

    case $size_suffix in
      "GiB")
        let "size_bytes = $size * 1073741824"
      ;;
      "MiB")
        let "size_bytes = $size * 10485761"
      ;;
      "KiB")
        let "size_bytes = $size * 1024"
      ;;
      *)
        size_bytes=0
      ;;
    esac

    # JSON output formatting
    $first_entry || echo "," >> "$OUTPUT"
    first_entry=false

    cat <<EOF >> "$OUTPUT"
    {
      "vmid": "$vmid",
      "name": $name,
      "node": "$NODE",
      "start": $start_ts,
      "end": $end_ts,
      "duration": $duration,
      "status": "$status",
      "size_bytes": $size_bytes,
      "error": $error_json
    }
EOF

done

echo "] }" >> "$OUTPUT"

#list VM without backup
/usr/bin/pvesh get /cluster/backup-info/not-backed-up --output-format json  > "$NONBACKUPLOG"
#
