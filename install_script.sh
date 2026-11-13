#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND="noninteractive"

apt-get update --assume-yes
apt-get dist-upgrade --assume-yes
apt-get install --assume-yes --no-install-recommends apt-transport-https ca-certificates curl jq tar zstd

# The GitHub API is called with the token from the build secret github_token when it is given
# (60 requests per hour without it, 1000 with the GITHUB_TOKEN of GitHub Actions)
GITHUB_API_ARGUMENTS=()
if [ -s '/run/secrets/github_token' ]; then
    GITHUB_API_ARGUMENTS=(--header "Authorization: Bearer $(cat '/run/secrets/github_token')")
fi

DEBIAN_ARCHITECTURE="$(dpkg --print-architecture)"

case "$DEBIAN_ARCHITECTURE" in
    'amd64' | 'arm64')
        ;;
    *) echo "Unknown architecture ${DEBIAN_ARCHITECTURE}" >&2
       exit 1
       ;;
esac

{
    REPOSITORY_SLUG='mikefarah/yq'
    OS='linux'
    ARCHITECTURE="$DEBIAN_ARCHITECTURE"
    SUFFIX='.tar.gz'
    SOURCE_FILE_NAME="./yq_linux_${ARCHITECTURE}"
    TARGET_FILE_PATH='/usr/local/bin/yq'

    DOWNLOAD_URL=$(curl --retry 3 --retry-all-errors --silent --location --show-error --fail "${GITHUB_API_ARGUMENTS[@]}" --url "https://api.github.com/repos/${REPOSITORY_SLUG}/releases/latest" | jq -r '.assets[].browser_download_url' | sed --silent --regexp-extended 's/^(.*'"$OS"'.*'"$ARCHITECTURE"'.*'"$SUFFIX"')$/\1/p')

    TEMPORARY_FILE=$(mktemp)
    TEMPORARY_DIRECTORY=$(mktemp --directory)

    curl --retry 3 --retry-all-errors --location --silent --fail --show-error --output "$TEMPORARY_FILE" --url "$DOWNLOAD_URL"
    tar xvf "$TEMPORARY_FILE" -C "$TEMPORARY_DIRECTORY"

    cp --remove-destination --recursive --no-dereference --preserve=mode,links,timestamps "${TEMPORARY_DIRECTORY}/${SOURCE_FILE_NAME}" "$TARGET_FILE_PATH"
}

{
    REPOSITORY_SLUG='aptible/supercronic'
    OS='linux'
    ARCHITECTURE="$DEBIAN_ARCHITECTURE"
    TARGET_FILE_PATH='/usr/local/bin/supercronic'

    DOWNLOAD_URL=$(curl --retry 3 --retry-all-errors --silent --location --show-error --fail "${GITHUB_API_ARGUMENTS[@]}" --url "https://api.github.com/repos/${REPOSITORY_SLUG}/releases/latest" | jq -r '.assets[].browser_download_url' | sed --silent --regexp-extended 's/^(.*'"$OS"'.*'"$ARCHITECTURE"')$/\1/p')

    TEMPORARY_FILE=$(mktemp)

    curl --retry 3 --retry-all-errors --location --silent --fail --show-error --remote-time --output "$TEMPORARY_FILE" --url "$DOWNLOAD_URL"
    install --mode 0755 --preserve-timestamps "$TEMPORARY_FILE" "$TARGET_FILE_PATH"
}

cat > /etc/apt/preferences.d/no-debian-postgresql <<'EOF'
Package: postgresql postgresql-* libpq* libecpg* libpgtypes* pgdg-* pg-*
Pin: release o=Debian
Pin-Priority: -1
EOF

install --directory --mode 0755 '/etc/apt/keyrings'

curl --retry 3 --retry-all-errors --silent --location --show-error --fail --output '/etc/apt/keyrings/postgresql.asc' 'https://www.postgresql.org/media/keys/ACCC4CF8.asc'
cat > '/etc/apt/sources.list.d/pgdg.list' <<EOF
deb [signed-by=/etc/apt/keyrings/postgresql.asc] https://apt.postgresql.org/pub/repos/apt ${DEBIAN_CODENAME}-pgdg main
EOF

apt-get update --assume-yes

CONFIGURATION_FILE_PATH='/mnt/docker/configuration.yaml'

DEBIAN_PACKAGE=$(yq --exit-status '.postgresql_versions[strenv(POSTGRESQL_VERSION)].postgresql[strenv(DEBIAN_CODENAME)].version' "$CONFIGURATION_FILE_PATH")

apt-get install --assume-yes --no-install-recommends "$DEBIAN_PACKAGE"

rm --recursive --force /var/cache/apt/*.bin /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/* /var/lib/apt/lists/* /tmp/* 2>/dev/null || true
