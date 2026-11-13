#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SOURCE_URL="${SOURCE_URL:-https://github.com/alpinium/postgresql-backup-restore}"
VCS_REF="${VCS_REF:-}"
BUILD_DATE="${BUILD_DATE:-}"
# Version of the scripts from the file VERSION
RELEASE_VERSION="${RELEASE_VERSION:-}"

if ! [[ $DEBIAN_POINT_RELEASE =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "Unexpected /etc/debian_version: \"${DEBIAN_POINT_RELEASE}\"" >&2
    exit 1
fi

cat <<EOF
org.opencontainers.image.title=postgresql-backup-restore
org.opencontainers.image.description=PostgreSQL-Backup-Restore image for Alpinium projects
org.opencontainers.image.vendor=Alpinium Tech
org.opencontainers.image.authors=Alpinium Tech <alpinium@alpinium.tech>
org.opencontainers.image.url=https://hub.docker.com/r/alpiniumtech/postgresql-backup-restore
org.opencontainers.image.source=${SOURCE_URL}
org.opencontainers.image.documentation=${SOURCE_URL}#readme
org.opencontainers.image.licenses=Apache-2.0
org.opencontainers.image.version=${POSTGRESQL_VERSION}-${DEBIAN_CODENAME}${RELEASE_VERSION:+-${RELEASE_VERSION}}
org.opencontainers.image.revision=${VCS_REF}
org.opencontainers.image.created=${BUILD_DATE}
org.opencontainers.image.base.name=docker.io/library/debian:${DEBIAN_CODENAME}-slim
postgresql_backup_restore.version=${POSTGRESQL_VERSION}
postgresql_backup_restore.major=${POSTGRESQL_MAJOR}
postgresql_backup_restore.release=${RELEASE_VERSION}
debian.codename=${DEBIAN_CODENAME}
debian.release=${DEBIAN_POINT_RELEASE%%.*}
debian.point-release=${DEBIAN_POINT_RELEASE}
EOF
