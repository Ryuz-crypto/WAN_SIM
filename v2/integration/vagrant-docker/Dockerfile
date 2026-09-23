ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV container=docker DEBIAN_FRONTEND=noninteractive

RUN if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl dbus openssl procps sudo systemd systemd-sysv && \
      rm -rf /var/lib/apt/lists/*; \
    else \
      dnf -y install ca-certificates curl-minimal dbus openssl procps-ng sudo systemd && \
      dnf clean all; \
    fi && \
    systemctl mask systemd-remount-fs.service getty@.service console-getty.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
