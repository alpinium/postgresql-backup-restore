#!/bin/bash

# Deletes the backup and restore logs (backup_YYYYMMDDTHHMMSS.log, restore_YYYYMMDDTHHMMSS.log) in the current directory
# whose timestamp in the file name (UTC) is older than the given number of days.
# Files whose name does not match this pattern are left untouched.
#
# Usage: ./delete_old_logs.sh [--retention-days days]
#   --retention-days days    keep logs younger than this many days (default: 30)

set -euo pipefail
IFS=$'\n\t'

RETENTION_DAYS='30'

function PrintUsage()
{
    echo "Usage: $0 [--retention-days days]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --retention-days)
            RETENTION_DAYS="${2:?$1 requires a value}"
            shift 2
            ;;
        *)
            echo "$0: unknown argument -- '$1'" >&2
            PrintUsage
            exit 2
            ;;
    esac
done

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    echo "$0: --retention-days must be a non-negative integer -- '${RETENTION_DAYS}'" >&2
    PrintUsage
    exit 2
fi

CUTOFF=$(date --utc --date "-$((10#$RETENTION_DAYS)) days" '+%Y%m%dT%H%M%S')

echo "Deleting backup and restore logs older than ${RETENTION_DAYS} days (before ${CUTOFF} UTC)"

while read -r LOG_FILE; do
    if ! [[ "$LOG_FILE" =~ ^(backup|restore)_([0-9]{8}T[0-9]{6})\.log$ ]]; then
        continue
    fi

    # The timestamp has a fixed format, so the string comparison orders it chronologically.
    if [[ "${BASH_REMATCH[2]}" < "$CUTOFF" ]]; then
        rm --force -- "$LOG_FILE"
        echo "Deleted ${LOG_FILE}"
    fi
done < <(find . -maxdepth 1 -type f \( -name 'backup_*.log' -o -name 'restore_*.log' \) -printf '%f\n')
