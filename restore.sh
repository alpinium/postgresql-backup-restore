#!/bin/bash

# Restores a backup created by backup.sh:
#   <database>_YYYYMMDDTHHMMSS.sql.zst          the database
#   <database>_scheme_YYYYMMDDTHHMMSS.sql.zst   the database (--split), given as the first --file,
#   <database>_data_YYYYMMDDTHHMMSS.sql.zst     together with its data, given as the second --file
#   __globals_YYYYMMDDTHHMMSS.sql.zst           the globals (roles, tablespaces)
#
# The kind of the backup is recognized from the file name. The backup files are tested first.
# When the database given by --dbname already exists, it is dropped (with its connections terminated),
# after the user confirms it by typing "yes". After the restore, VACUUM ANALYZE is run on the database.
# The output is also written to restore_YYYYMMDDTHHMMSS.log in the current directory (time is in UTC).
#
# Usage: ./restore.sh -h hostname [-p port] [-U username] [-d dbname] -f backup_file [-f data_file]
#   -h, --host hostname      server host (required)
#   -p, --port port          server port (default: 5432)
#   -U, --username username  user name (default: postgres)
#   -d, --dbname dbname      name of the restored database (required; must be omitted for the globals)
#   -f, --file backup_file   backup file to restore (required); for a split backup given twice,
#                            first the _scheme_ file, then the _data_ file
#   The password is taken by libpq from PGPASSWORD (or ~/.pgpass).

set -euo pipefail
IFS=$'\n\t'

HOST=''
PORT='5432'
USERNAME='postgres'
DBNAME=''
BACKUP_FILES=()

function PrintUsage()
{
    echo "Usage: $0 -h hostname [-p port] [-U username] [-d dbname] -f backup_file [-f data_file]" >&2
}

function Decompress()
{
    set -euo pipefail

    local FILE="$1"

    zstd --decompress --quiet --stdout --long=27 -- "$FILE"
}

function TestBackupFile()
{
    set -euo pipefail

    local FILE="$1"

    echo "Testing ${FILE}"

    if ! zstd --test --quiet --long=27 -- "$FILE"; then
        echo "$0: backup file is corrupted -- '${FILE}'" >&2
        exit 1
    fi
}

function Psql()
{
    set -euo pipefail

    psql --host "$HOST" --port "$PORT" --username "$USERNAME" --no-password --no-psqlrc "$@"
}

function DatabaseConnectionString()
{
    set -euo pipefail

    local DATABASE="$1"

    # Backslashes and apostrophes have to be escaped inside a quoted connection string value.
    DATABASE="${DATABASE//\\/\\\\}"
    DATABASE="${DATABASE//\'/\\\'}"

    echo "dbname='${DATABASE}'"
}

function DatabaseExists()
{
    set -euo pipefail

    local DATABASE="$1"

    local RESULT
    if ! RESULT=$(Psql --dbname 'postgres' --tuples-only --no-align --variable ON_ERROR_STOP=1 \
                       --variable db="$DATABASE" <<'EOF'
SELECT 1 FROM pg_database WHERE datname = :'db'
EOF
); then
        echo "Failed to check whether database ${DATABASE} exists ${HOST}:${PORT} as ${USERNAME}" >&2
        exit 1
    fi

    [ "$RESULT" = '1' ]
}

function DropDatabase()
{
    set -euo pipefail

    local DATABASE="$1"

    local ANSWER=''
    echo -n "Are you sure you want to permanently and irretrievably delete the entire database ${DATABASE}? yes/no " >&2
    read -r ANSWER || true
    echo "$ANSWER"

    if [ "$ANSWER" != 'yes' ]; then
        echo "Restore cancelled, database ${DATABASE} was not changed" >&2
        exit 1
    fi

    echo "Dropping database ${DATABASE} ${HOST}:${PORT} as ${USERNAME}"

    # FORCE terminates the connections to the database, otherwise DROP DATABASE fails.
    Psql --dbname 'postgres' --quiet --variable ON_ERROR_STOP=1 --variable db="$DATABASE" <<'EOF'
DROP DATABASE :"db" WITH (FORCE);
EOF
}

function RestoreFile()
{
    set -euo pipefail

    local FILE="$1"
    shift

    echo "Restoring ${FILE} to ${HOST}:${PORT} as ${USERNAME}"

    # The query results are discarded, the errors still go to stderr.
    if ! Decompress "$FILE" | Psql "$@" --quiet --output /dev/null; then
        echo "Failed restore ${FILE} to ${HOST}:${PORT} as ${USERNAME}" >&2
        return 1
    fi

    echo "Restored ${FILE} to ${HOST}:${PORT} as ${USERNAME}"
}

function VacuumAnalyzeDatabase()
{
    set -euo pipefail

    echo "Vacuuming and analyzing database ${DBNAME} ${HOST}:${PORT} as ${USERNAME}"

    if ! Psql --dbname "$(DatabaseConnectionString "$DBNAME")" --quiet --variable ON_ERROR_STOP=1 <<'EOF'
VACUUM ANALYZE;
EOF
    then
        echo "Failed vacuum and analyze database ${DBNAME} ${HOST}:${PORT} as ${USERNAME}" >&2
        return 1
    fi

    echo "Vacuumed and analyzed database ${DBNAME} ${HOST}:${PORT} as ${USERNAME}"
}

function RestoreGlobals()
{
    set -euo pipefail

    if [ -n "$DBNAME" ]; then
        echo "$0: the globals do not belong to a database, omit -d dbname" >&2
        PrintUsage
        exit 2
    fi

    TestBackupFile "$BACKUP_FILE"

    # Without ON_ERROR_STOP: the roles that already exist (at least the connecting one) report an error.
    RestoreFile "$BACKUP_FILE" --dbname 'postgres'
}

function PrepareDatabase()
{
    set -euo pipefail

    if [ -z "$DBNAME" ]; then
        echo "$0: database not specified (-d dbname)" >&2
        PrintUsage
        exit 2
    fi

    # The backup files are tested before the database is dropped.
    local FILE
    for FILE in "$@"; do
        TestBackupFile "$FILE"
    done

    if DatabaseExists "$DBNAME"; then
        DropDatabase "$DBNAME"
    fi
}

function RestoreDatabase()
{
    set -euo pipefail

    PrepareDatabase "$BACKUP_FILE"

    # The backup creates the database and connects to it by itself.
    RestoreFile "$BACKUP_FILE" --dbname 'postgres' --variable ON_ERROR_STOP=1 || return 1

    VacuumAnalyzeDatabase
}

function RestoreSplitDatabase()
{
    set -euo pipefail

    PrepareDatabase "$BACKUP_FILE" "$DATA_FILE"

    # The schema creates the database and connects to it by itself, the data are loaded into it.
    RestoreFile "$BACKUP_FILE" --dbname 'postgres' --variable ON_ERROR_STOP=1 || return 1
    RestoreFile "$DATA_FILE" --dbname "$(DatabaseConnectionString "$DBNAME")" --variable ON_ERROR_STOP=1 || return 1

    VacuumAnalyzeDatabase
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
            DBNAME="${2:?$1 requires a value}"
            shift 2
            ;;
        -f|--file)
            BACKUP_FILES+=("${2:?$1 requires a value}")
            shift 2
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

if [ "${#BACKUP_FILES[@]}" -eq 0 ]; then
    echo "$0: backup file not specified (-f backup_file)" >&2
    PrintUsage
    exit 2
fi

if [ "${#BACKUP_FILES[@]}" -gt 2 ]; then
    echo "$0: too many backup files, -f can be given at most twice" >&2
    PrintUsage
    exit 2
fi

for FILE in "${BACKUP_FILES[@]}"; do
    if [ ! -f "$FILE" ]; then
        echo "$0: backup file not found -- '${FILE}'" >&2
        exit 2
    fi
done

BACKUP_FILE="${BACKUP_FILES[0]}"
DATA_FILE="${BACKUP_FILES[1]:-}"

TIMESTAMP=$(date --utc '+%Y%m%dT%H%M%S')

exec > >(tee "restore_${TIMESTAMP}.log") 2>&1
TEE_PID=$!

function TrapExit()
{
    # Lets tee write the rest of the log before the script ends.
    exec >&- 2>&-
    wait "$TEE_PID"
}

trap TrapExit EXIT

SCHEME_REGEX='^.+_scheme_[0-9]{8}T[0-9]{6}\.sql\.zst$'
DATA_REGEX='^.+_data_[0-9]{8}T[0-9]{6}\.sql\.zst$'

BACKUP_FILE_NAME=$(basename -- "$BACKUP_FILE")

if [ -n "$DATA_FILE" ]; then
    if ! [[ "$BACKUP_FILE_NAME" =~ $SCHEME_REGEX ]]; then
        echo "$0: the first file of a split backup must be the _scheme_ file -- '${BACKUP_FILE}'" >&2
        exit 2
    fi

    if ! [[ "$(basename -- "$DATA_FILE")" =~ $DATA_REGEX ]]; then
        echo "$0: the second file of a split backup must be the _data_ file -- '${DATA_FILE}'" >&2
        exit 2
    fi

    RestoreSplitDatabase
elif [[ "$BACKUP_FILE_NAME" =~ ^__globals_[0-9]{8}T[0-9]{6}\.sql\.zst$ ]]; then
    RestoreGlobals
elif [[ "$BACKUP_FILE_NAME" =~ $SCHEME_REGEX ]]; then
    echo "$0: ${BACKUP_FILE} is the schema part of a split backup, give its _data_ file as the second -f" >&2
    exit 2
elif [[ "$BACKUP_FILE_NAME" =~ $DATA_REGEX ]]; then
    echo "$0: ${BACKUP_FILE} is the data part of a split backup, give -f with the _scheme_ file first, then -f with this one" >&2
    exit 2
elif [[ "$BACKUP_FILE_NAME" =~ ^.+_[0-9]{8}T[0-9]{6}\.sql\.zst$ ]]; then
    RestoreDatabase
else
    echo "$0: unknown backup file name format -- '${BACKUP_FILE}'" >&2
    exit 2
fi
