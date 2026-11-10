#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

BASE_PATH=$(readlink --canonicalize "${BASH_SOURCE:-$0}")
BASE_DIRECTORY="${BASE_PATH%/*}"

CONFIGURATION_YAML_PATH="${BASE_DIRECTORY}/../configuration.yaml"

declare -x MAJOR_VERSION
readarray -t MAJOR_VERSIONS < <(yq '.postgresql_versions | keys | .[]' "$CONFIGURATION_YAML_PATH")
for MAJOR_VERSION in "${MAJOR_VERSIONS[@]}"; do

    declare -x DEBIAN_CODENAME
    readarray -t DEBIAN_CODENAMES < <(yq '.postgresql_versions[strenv(MAJOR_VERSION)].debian[]' "$CONFIGURATION_YAML_PATH")
    for DEBIAN_CODENAME in "${DEBIAN_CODENAMES[@]}"; do

        declare -x POSTGRESQL_VERSION
        POSTGRESQL_VERSION=$(curl --silent --location --show-error --fail --url "https://apt.postgresql.org/pub/repos/apt/dists/${DEBIAN_CODENAME}-pgdg/main/binary-amd64/Packages.gz" | \
                             gunzip | sed --regexp-extended --silent "/^Package: /{s/^Package: //;h;};/^Version: /{s/^Version: //;H;x;s/\n/ /;/^postgresql-client-${MAJOR_VERSION} /p;}" | sort --reverse --version-sort | head -n1)

        POSTGRESQL_VERSION="${POSTGRESQL_VERSION// /=}"
        echo "POSTGRESQL ${POSTGRESQL_VERSION}"

        yq -i 'with(.postgresql_versions[strenv(MAJOR_VERSION)].postgresql[strenv(DEBIAN_CODENAME)].version; . = strenv(POSTGRESQL_VERSION) | . style="single")' "$CONFIGURATION_YAML_PATH"

    done

done
