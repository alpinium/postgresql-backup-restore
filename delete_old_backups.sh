#!/bin/bash

# Deletes the backups created by backup.sh in the current directory whose timestamp
# in the file name (UTC) is older than the given number of days:
#   <database>_YYYYMMDDTHHMMSS.sql.zst
#   <database>_scheme_YYYYMMDDTHHMMSS.sql.zst
#   <database>_data_YYYYMMDDTHHMMSS.sql.zst
#   __globals_YYYYMMDDTHHMMSS.sql.zst (globals)
# Files whose name does not match these patterns are left untouched.
#
# Usage: ./delete_old_backups.sh [--retention-days days] [--dbname dbname]
#   --retention-days days    keep backups younger than this many days (default: 30)
#   --dbname dbname          delete only the backups of this database
#                            (default: the backups of all databases and the globals)

set -euo pipefail
IFS=$'\n\t'

RETENTION_DAYS='30'
DBNAME=''

function PrintUsage()
{
    echo "Usage: $0 [--retention-days days] [--dbname dbname]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --retention-days)
            RETENTION_DAYS="${2:?$1 requires a value}"
            shift 2
            ;;
        --dbname)
            DBNAME="${2?$1 requires a value}"
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

# The same transformation of the database name as in backup.sh.
FILE_PREFIX="${DBNAME//[^A-Za-z0-9._-]/_}"

CUTOFF=$(date --utc --date "-$((10#$RETENTION_DAYS)) days" '+%Y%m%dT%H%M%S')

if [ -z "$DBNAME" ]; then
    echo "Deleting all backups older than ${RETENTION_DAYS} days (before ${CUTOFF} UTC)"
else
    echo "Deleting backups of database ${DBNAME} older than ${RETENTION_DAYS} days (before ${CUTOFF} UTC)"
fi

while read -r BACKUP_FILE; do
    if ! [[ "$BACKUP_FILE" =~ ^([A-Za-z0-9._-]+)_([0-9]{8}T[0-9]{6})\.sql\.zst$ ]]; then
        continue
    fi

    BACKUP_PREFIX="${BASH_REMATCH[1]}"
    BACKUP_TIMESTAMP="${BASH_REMATCH[2]}"

    if [ -n "$DBNAME" ] && [ "$BACKUP_PREFIX" != "$FILE_PREFIX" ] \
        && [ "$BACKUP_PREFIX" != "${FILE_PREFIX}_scheme" ] && [ "$BACKUP_PREFIX" != "${FILE_PREFIX}_data" ]; then
        continue
    fi

    # The timestamp has a fixed format, so the string comparison orders it chronologically.
    if [[ "$BACKUP_TIMESTAMP" < "$CUTOFF" ]]; then
        rm --force -- "$BACKUP_FILE"
        echo "Deleted ${BACKUP_FILE}"
    fi
done < <(find . -maxdepth 1 -type f -name '*.sql.zst' -printf '%f\n')
