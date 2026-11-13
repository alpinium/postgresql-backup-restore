ARG DEBIAN_CODENAME=""
ARG POSTGRESQL_VERSION=""

FROM debian:${DEBIAN_CODENAME}-slim

ARG DEBIAN_CODENAME=""
ARG POSTGRESQL_VERSION=""
ENV DEBIAN_CODENAME=${DEBIAN_CODENAME}
ENV POSTGRESQL_VERSION=${POSTGRESQL_VERSION}

# The optional secret github_token raises the GitHub API rate limit in install_script.sh,
# it is not stored in the image
RUN --mount=type=secret,id=github_token \
    --mount=type=bind,source=install_script.sh,target=/mnt/docker/install_script.sh \
    --mount=type=bind,source=configuration.yaml,target=/mnt/docker/configuration.yaml \
    bash /mnt/docker/install_script.sh

ADD backup.sh /usr/local/bin/backup.sh
ADD restore.sh /usr/local/bin/restore.sh
ADD delete_old_backups.sh /usr/local/bin/delete_old_backups.sh
ADD delete_old_logs.sh /usr/local/bin/delete_old_logs.sh
ADD docker-entrypoint.sh /docker-entrypoint.sh

STOPSIGNAL SIGTERM

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD []
