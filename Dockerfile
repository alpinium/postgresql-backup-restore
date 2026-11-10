ARG DEBIAN_CODENAME=""
ARG POSTGRESQL_VERSION=""

FROM debian:${DEBIAN_CODENAME}-slim

ARG DEBIAN_CODENAME=""
ARG POSTGRESQL_VERSION=""
ENV DEBIAN_CODENAME=${DEBIAN_CODENAME}
ENV POSTGRESQL_VERSION=${POSTGRESQL_VERSION}

RUN --mount=type=bind,source=install_script.sh,target=/mnt/docker/install_script.sh \
    --mount=type=bind,source=configuration.yaml,target=/mnt/docker/configuration.yaml \
    bash /mnt/docker/install_script.sh

ADD backup.sh /usr/local/bin/backup.sh
ADD docker-entrypoint.sh /docker-entrypoint.sh

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/bin/tini", "--", "/docker-entrypoint.sh"]

CMD []
