#!/bin/bash

# Without arguments, runs supercronic:
#   - with the crontab /etc/supercronic/crontab, when it is mounted into the container,
#   - otherwise with a crontab created from the environment variables CRON_JOB_<name>,
#     each of them is one crontab line (schedule and command), in the order of their names, e.g.
#       CRON_JOB_BACKUP='0 3 * * * cd /backup && backup.sh -h db'
#     (empty variables are skipped),
#   - fails only when the crontab is not mounted and no CRON_JOB_<name> variable is filled.
# With arguments, runs the given command.

set -euo pipefail
IFS=$'\n\t'

CRONTAB_FILE='/etc/supercronic/crontab'
GENERATED_CRONTAB_FILE='/tmp/supercronic-crontab'

function ListCronJobVariables()
{
    set -euo pipefail

    local VARIABLE

    for VARIABLE in $(compgen -e | grep '^CRON_JOB_' | LC_ALL=C sort || true); do
        if [ -n "${!VARIABLE}" ]; then
            echo "$VARIABLE"
        fi
    done
}

function CreateCrontab()
{
    set -euo pipefail

    local VARIABLE

    : > "$GENERATED_CRONTAB_FILE"

    for VARIABLE in "$@"; do
        echo "${!VARIABLE}" >> "$GENERATED_CRONTAB_FILE"
    done
}

if [ "$#" -eq 0 ]; then
    readarray -t CRON_JOB_VARIABLES < <(ListCronJobVariables)

    if [ -f "$CRONTAB_FILE" ]; then
        if [ "${#CRON_JOB_VARIABLES[@]}" -gt 0 ]; then
            echo "$0: crontab ${CRONTAB_FILE} is mounted, the CRON_JOB_* environment variables are ignored" >&2
        fi

        set -- /usr/local/bin/supercronic "$CRONTAB_FILE"
    elif [ "${#CRON_JOB_VARIABLES[@]}" -gt 0 ]; then
        CreateCrontab "${CRON_JOB_VARIABLES[@]}"

        echo "Crontab created from the CRON_JOB_* environment variables:"
        cat "$GENERATED_CRONTAB_FILE"

        set -- /usr/local/bin/supercronic "$GENERATED_CRONTAB_FILE"
    else
        echo "$0: no crontab, mount it to ${CRONTAB_FILE} or set the CRON_JOB_* environment variables" >&2
        exit 1
    fi
fi

exec "$@"
