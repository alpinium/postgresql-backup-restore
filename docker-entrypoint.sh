#!/bin/bash

set -euo pipefail

if [ "$#" -eq 0 ]; then
    set -- cron -f
fi

exec "$@"
