#!/bin/bash

log_dir="/var/log/vzdump"
output_file="/var/log/backups.log"
hostname="pve"

echo '{ "backups": [' > "$output_file"

first=1

for log_file in "$log_dir"/*.log; do
    [[ -e "$log_file" ]] || continue

    vmid=$(basename "$log_file" | cut -d'-' -f2 | cut -d'.' -f1)
    name="null"
    start=0
    end=0
    status="FAILED"
    size_bytes=0

    while IFS= read -r line; do
        if [[ "$line" =~ Starting\ Backup\ of\ VM ]]; then
            start=$(date -d "$(echo "$line" | cut -d' ' -f1-2)" +%s)
        elif [[ "$line" =~ "VM Name:" ]]; then
            name=$(echo "$line" | sed -n 's/.*VM Name: \(.*\)/\1/p' | sed 's/"/\\"/g')
        elif [[ "$line" =~ "transferred" ]]; then
            size_bytes=$(echo "$line" | grep -oE '[0-9.]+ [KMGT]iB' | sed 's/ //g' | numfmt --from=iec 2>/dev/null)
            [[ -z "$size_bytes" ]] && size_bytes=0
        elif [[ "$line" =~ "Finished Backup" ]]; then
            status="OK"
        fi
        end=$(date -d "$(echo "$line" | cut -d' ' -f1-2)" +%s)
    done < "$log_file"

    # Wenn "status = running" in Log steht, aber kein "Finished Backup"
    if grep -q "INFO: status = running" "$log_file" && ! grep -q "INFO: Finished Backup" "$log_file"; then
        status="running"
    fi

    [[ $first -eq 0 ]] && echo "," >> "$output_file"
    first=0

    cat <<EOF >> "$output_file"
  {
    "vmid": "$vmid",
    "name": "$name",
    "node": "$hostname",
    "start": $start,
    "end": $end,
    "status": "$status",
    "size_bytes": $size_bytes
  }
EOF

done

echo "] }" >> "$output_file"
