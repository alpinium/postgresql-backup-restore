#!/bin/bash

# Backs up the databases, one after another, to separate plain SQL files
# compressed with zstd, in the current directory (time is in UTC):
#   <database>_YYYYMMDDTHHMMSS.sql.zst
#   <database>_scheme_YYYYMMDDTHHMMSS.sql.zst + <database>_data_YYYYMMDDTHHMMSS.sql.zst (--split)
#   __globals_YYYYMMDDTHHMMSS.sql.zst (--globals)
#
# Usage: ./backup.sh -h hostname [-p port] [-U username] [-d dbname] [--split] [--globals]
#   -h, --host hostname      server host (required)
#   -p, --port port          server port (default: 5432)
#   -U, --username username  user name (default: postgres)
#   -d, --dbname dbname      name of the database to back up (default: all databases)
#   --split                  back up the schema and the data of each database to separate files
#   --globals                back up only the globals (roles, tablespaces), nothing else
#   The password is taken by libpq from PGPASSWORD (or ~/.pgpass).

set -euo pipefail
IFS=$'\n\t'

HOST=''
PORT='5432'
USERNAME='postgres'
DBNAME=''
GLOBALS=0
SPLIT=0

function PrintUsage()
{
    echo "Usage: $0 -h hostname [-p port] [-U username] [-d dbname] [--split] [--globals]" >&2
}

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
    local BACKUP_FILE="__globals_${TIMESTAMP}.sql.zst"
    echo "Backing up globals ${HOST}:${PORT} as ${USERNAME} to ${BACKUP_FILE}"

    local TEMPORARY_FILE=$(mktemp ".${BACKUP_FILE}.XXXXXX")
    TEMPORARY_FILES+=("$TEMPORARY_FILE")
    
    if ! pg_dumpall --host "$HOST" --port "$PORT" --username "$USERNAME" --no-password --globals-only | Compress > "$TEMPORARY_FILE"; then
        echo "Failed backup globals ${HOST}:${PORT} as ${USERNAME} to ${BACKUP_FILE}" >&2
        return 1
    fi

    mv --force "$TEMPORARY_FILE" "$BACKUP_FILE"
    echo "Backed up globals ${HOST}:${PORT} as ${USERNAME} to ${BACKUP_FILE}"
}

function ListDatabases()
{
    set -euo pipefail

    psql --host "$HOST" --port "$PORT" --username "$USERNAME" --no-password --dbname 'postgres' \
         --no-psqlrc --tuples-only --no-align --variable ON_ERROR_STOP=1 <<'EOF'
SELECT datname FROM pg_database
WHERE datallowconn AND (NOT datistemplate) AND (datname NOT IN ('postgres', 'template0', 'template1'))
ORDER BY datname
EOF
}

function DumpDatabase()
{
    set -euo pipefail

    local DATABASE="$1"
    local BACKUP_FILE="$2"
    shift 2

    echo "Backing up database ${DATABASE} ${HOST}:${PORT} as ${USERNAME} to ${BACKUP_FILE}"

    local TEMPORARY_FILE=$(mktemp ".${BACKUP_FILE}.XXXXXX")
    TEMPORARY_FILES+=("$TEMPORARY_FILE")

    if ! pg_dump --host "$HOST" --port "$PORT" --no-password --username "$USERNAME" \
        --format=plain "$@" --dbname "dbname='${DATABASE}'" | Compress > "$TEMPORARY_FILE"; then

        echo "Failed backup database ${DATABASE} ${HOST}:${PORT} as ${USERNAME} to ${BACKUP_FILE}" >&2
        return 1
    fi

    mv --force "$TEMPORARY_FILE" "$BACKUP_FILE"
    echo "Backed up database ${DATABASE} ${HOST}:${PORT} as ${USERNAME} to ${BACKUP_FILE}"
}

function BackupDatabase()
{
    set -euo pipefail

    local DATABASE="$1"

    local TIMESTAMP=$(date --utc '+%Y%m%dT%H%M%S')
    local FILE_PREFIX="${DATABASE//[^A-Za-z0-9._-]/_}"

    if [ "$SPLIT" -eq 1 ]; then
        DumpDatabase "$DATABASE" "${FILE_PREFIX}_scheme_${TIMESTAMP}.sql.zst" --create --schema-only || return 1
        DumpDatabase "$DATABASE" "${FILE_PREFIX}_data_${TIMESTAMP}.sql.zst" --data-only || return 1
    else
        DumpDatabase "$DATABASE" "${FILE_PREFIX}_${TIMESTAMP}.sql.zst" --create || return 1
    fi
}


while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--host)
            HOST="${2:?$1 requires a value}"
            shift 2
            ;;
        -p|--port)
            PORT="${2:?$1 requires a value}"
            shift 2
            ;;
        -U|--username)
            USERNAME="${2:?$1 requires a value}"
            shift 2
            ;;
        -d|--dbname)
            DBNAME="${2?$1 requires a value}"
            shift 2
            ;;
        --split)
            SPLIT=1
            shift
            ;;
        --globals)
            GLOBALS=1
            shift
            ;;
        *)
            echo "$0: unknown argument -- '$1'" >&2
            PrintUsage
            exit 2
            ;;
    esac
done

if [ -z "$HOST" ]; then
    echo "$0: host not specified (-h hostname)" >&2
    PrintUsage
    exit 2
fi

FAILED=0
TIMESTAMP=$(date --utc '+%Y%m%dT%H%M%S')

exec > >(tee "backup_${TIMESTAMP}.log") 2>&1
TEE_PID=$!

if [ "$GLOBALS" -eq 1 ]; then
    BackupGlobals || FAILED=1
elif [ -n "$DBNAME" ]; then
    BackupDatabase "$DBNAME" || FAILED=1
else
    while read -r DATABASE; do
        BackupDatabase "$DATABASE" || FAILED=1
    done < <(ListDatabases)
    wait $!
fi

exec >&- 2>&-
wait "$TEE_PID"

exit "$FAILED"
