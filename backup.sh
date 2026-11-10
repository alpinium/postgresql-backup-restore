#!/bin/bash

# Backs up the globals and then every database, one after another, to separate
# plain SQL files compressed with zstd, in the current directory (time is in UTC):
#   __backup_YYYYMMDDTHHMMSS.sql.zst
#   <database>_YYYYMMDDTHHMMSS.sql.zst
#
# Usage: ./backup.sh
#   The connection is configured with libpq variables (PGHOST, PGPORT, PGUSER, PGPASSWORD, ...).

set -euo pipefail
IFS=$'\n\t'

: "${PGHOST:=}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:=}"
: "${PGDATABASE:=}"

ZSTD_ARGUMENTS=('-19' '--long=27' '-T4')

TEMPORARY_FILES=()
function TrapExit()
{
    rm --recursive --force "${TEMPORARY_FILES[@]}"
}

trap TrapExit EXIT

function Compress()
{
    set -euo pipefail

    zstd --compress --quiet --force --stdout "${ZSTD_ARGUMENTS[@]}" -
}

function BackupGlobals()
{
    set -euo pipefail

    local TIMESTAMP=$(date --utc '+%Y%m%dT%H%M%S')
    local BACKUP_FILE="__backup_${TIMESTAMP}.sql.zst"
    echo "Backing up globals ${PGHOST}:${PGPORT} as ${PGUSER} to ${BACKUP_FILE}"

    local TEMPORARY_FILE=$(mktemp ".${BACKUP_FILE}.XXXXXX")
    TEMPORARY_FILES+=("$TEMPORARY_FILE")
    
    if ! pg_dumpall --host "$PGHOST" --port "$PGPORT" --username "$PGUSER" --no-password --globals-only | Compress > "$TEMPORARY_FILE"; then
        echo "Failed backup globals ${PGHOST}:${PGPORT} as ${PGUSER} to ${BACKUP_FILE}" >&2
        return 1
    fi

    mv --force "$TEMPORARY_FILE" "$BACKUP_FILE"
    echo "Backed up globals ${PGHOST}:${PGPORT} as ${PGUSER} to ${BACKUP_FILE}"
}

function ListDatabases()
{
    set -euo pipefail

    local USER_REGEX="${1:-.*}"
    psql --host "$PGHOST" --port "$PGPORT" --username "$PGUSER" --no-password --dbname 'postgres' \
         --no-psqlrc --tuples-only --no-align --variable ON_ERROR_STOP=1 --variable re="$USER_REGEX" <<'EOF'
SELECT datname FROM pg_database
WHERE datallowconn AND (NOT datistemplate) AND (datname NOT IN ('postgres', 'template0', 'template1')) AND (datname ~ :'re')
ORDER BY datname
EOF
}

function BackupDatabase()
{
    set -euo pipefail
    
    local DATABASE="$1"

    local TIMESTAMP=$(date --utc '+%Y%m%dT%H%M%S')
    local BACKUP_FILE="${DATABASE//[^A-Za-z0-9._-]/_}_${TIMESTAMP}.sql.zst"

    echo "Backing up database ${PGHOST}:${PGPORT} as ${PGUSER} to ${BACKUP_FILE}"

    local TEMPORARY_FILE=$(mktemp ".${BACKUP_FILE}.XXXXXX")
    TEMPORARY_FILES+=("$TEMPORARY_FILE")

    if ! pg_dump --host "$PGHOST" --port "$PGPORT" --no-password --username "$PGUSER" \
        --format=plain --create --dbname "dbname='${DATABASE}'" | Compress > "$TEMPORARY_FILE"; then

        echo "Failed backup database ${PGHOST}:${PGPORT} as ${PGUSER} to ${BACKUP_FILE}" >&2
        return 1
    fi

    mv --force "$TEMPORARY_FILE" "$BACKUP_FILE"
    echo "Backed up database ${PGHOST}:${PGPORT} as ${PGUSER} to ${BACKUP_FILE}"
}

FAILED=0
TIMESTAMP=$(date --utc '+%Y%m%dT%H%M%S')

exec > >(tee "backup_${TIMESTAMP}.log") 2>&1
TEE_PID=$!

if [ -z "$PGHOST" ]; then
    echo "PGHOST empty"
    exit 1
fi


if [ -z "$PGDATABASE" ]; then
    BackupGlobals
else
    while read -r DATABASE; do
        BackupDatabase "$DATABASE" || FAILED=1
    done < <(ListDatabases "$PGDATABASE")
    wait $!
fi

exec >&- 2>&-
wait "$TEE_PID"

exit "$FAILED"
