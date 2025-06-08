#!/bin/bash

LOG_DIR="/var/log/vzdump"
OUT_FILE="/var/log/backups.log"
NODE="pve"

echo '{ "backups": [' > "$OUT_FILE"
first=1

for log_file in "$LOG_DIR"/*.log; do
    [[ -e "$log_file" ]] || continue

    vmid=$(basename "$log_file" | grep -oE '[0-9]+')
    name="null"
    status="FAILED"
    size_bytes=0
    start_ts=$(stat -c %Y "$log_file")
    end_ts=$start_ts

    while IFS= read -r line; do
        # Name
        if [[ "$line" =~ "VM Name:" ]]; then
            name=$(echo "$line" | sed -n 's/.*VM Name: *//p')
        fi

        # Status
        if [[ "$line" =~ "INFO: Finished Backup" ]]; then
            status="OK"
        fi
        if [[ "$line" =~ "ERROR:" ]]; then
            status="FAILED"
        fi

        # Größe
        if [[ "$line" =~ "transferred" && "$line" =~ "in" ]]; then
            size_str=$(echo "$line" | grep -oP 'transferred \K[0-9.]+ [KMG]iB')
            if [[ "$size_str" =~ ([0-9.]+)\ ([KMG]iB) ]]; then
                num=${BASH_REMATCH[1]}
                unit=${BASH_REMATCH[2]}
                case $unit in
                    KiB) mult=1024 ;;
                    MiB) mult=1048576 ;;
                    GiB) mult=1073741824 ;;
                esac
                size_bytes=$(awk "BEGIN {printf \"%d\", $num * $mult}")
            fi
        fi

        end_ts=$(date +%s)
    done < "$log_file"

    [[ $first -eq 0 ]] && echo "," >> "$OUT_FILE"
    first=0

    echo "  {" >> "$OUT_FILE"
    echo "    \"vmid\": \"$vmid\"," >> "$OUT_FILE"
    echo "    \"name\": \"${name//\"/\\\"}\"," >> "$OUT_FILE"
    echo "    \"node\": \"$NODE\"," >> "$OUT_FILE"
    echo "    \"start\": $start_ts," >> "$OUT_FILE"
    echo "    \"end\": $end_ts," >> "$OUT_FILE"
    echo "    \"status\": \"$status\"," >> "$OUT_FILE"
    echo "    \"size_bytes\": $size_bytes" >> "$OUT_FILE"
    echo -n "  }" >> "$OUT_FILE"
done

echo "" >> "$OUT_FILE"
echo "] }" >> "$OUT_FILE"
