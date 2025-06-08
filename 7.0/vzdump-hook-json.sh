#!/bin/bash

LOG_DIR="/var/log/vzdump"
OUT_FILE="/var/log/backups.log"

# JSON-Datei überschreiben
echo '{ "backups": [' > "$OUT_FILE"
first=1

for logfile in "$LOG_DIR"/*.log; do
    vmid=$(basename "$logfile" | grep -oP '\d+')
    name=null
    node="pve"
    storage=null
    status="FAILED"
    size_bytes=0
    start_ts=$(stat -c %Y "$logfile")
    end_ts=$start_ts

    while IFS= read -r line; do
        # Name aus CT oder VM
        if [[ "$line" == *"CT Name:"* ]]; then
            match=$(echo "$line" | grep -oP "(?<=CT Name: ).+")
            [[ -n "$match" ]] && name="\"$match\""
        elif [[ "$line" == *"VM Name:"* ]]; then
            match=$(echo "$line" | grep -oP "(?<=VM Name: ).+")
            [[ -n "$match" ]] && name="\"$match\""
        fi

        # Storage aus --repository
        if [[ "$line" == *"--repository"* ]]; then
            match=$(echo "$line" | grep -oP -- "--repository\s+\S+@[^:]+:[^:]+(?=\s|$)" | grep -oP ":[^:]+$" | cut -c2-)
            [[ -n "$match" ]] && storage="\"$match\""
        fi

        # Fallback: Storage aus Upload-Ziel
        if [[ "$line" == *"Upload directory"* ]]; then
            match=$(echo "$line" | grep -oP "(?<=@)[^:]+:[^:]+(?='| )" | grep -oP ":[^:]+$" | cut -c2-)
            [[ -n "$match" && "$storage" == null ]] && storage="\"$match\""
        fi

        # Größe (falls vorhanden)
        if [[ "$line" == *"archive file size:"* ]]; then
            match=$(echo "$line" | grep -oP "(?<=archive file size: )\d+")
            [[ -n "$match" ]] && size_bytes="$match"
        fi

        # Status prüfen
        if echo "$line" | grep -iq "backup finished successfully"; then
            status="OK"
        fi

        # Zeitstempel
        if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            ts=$(date -d "${line:0:19}" +%s 2>/dev/null)
            if [[ -n "$ts" ]]; then
                [[ "$ts" -lt "$start_ts" ]] && start_ts="$ts"
                [[ "$ts" -gt "$end_ts" ]] && end_ts="$ts"
            fi
        fi
    done < "$logfile"

    [[ $first -eq 0 ]] && echo "," >> "$OUT_FILE"
    first=0

    echo -n "  {\"vmid\":\"$vmid\",\"name\":$name,\"node\":\"$node\",\"start\":$start_ts,\"end\":$end_ts,\"status\":\"$status\",\"storage\":$storage,\"size_bytes\":$size_bytes}" >> "$OUT_FILE"
done

echo -e "\n] }" >> "$OUT_FILE"
