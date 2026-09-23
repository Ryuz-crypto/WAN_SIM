ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV container=docker DEBIAN_FRONTEND=noninteractive

RUN if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl dbus openssh-server openssl procps sudo systemd systemd-sysv && \
      rm -rf /var/lib/apt/lists/*; \
    else \
      dnf -y install ca-certificates curl-minimal dbus openssh-clients openssh-server openssl procps-ng sudo systemd && \
      dnf clean all; \
    fi && \
    useradd --create-home --shell /bin/bash vagrant && \
    install -d -m 0700 -o vagrant -g vagrant /home/vagrant/.ssh && \
    curl -fsSL https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub \
      -o /home/vagrant/.ssh/authorized_keys && \
    chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys && \
    chmod 0600 /home/vagrant/.ssh/authorized_keys && \
    printf 'vagrant ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/vagrant && \
    chmod 0440 /etc/sudoers.d/vagrant && \
    ssh-keygen -A && \
    mkdir -p /run/sshd && \
    printf 'd /run/sshd 0755 root root -\n' > /etc/tmpfiles.d/wansim-sshd.conf && \
    install -d -m 0755 /etc/systemd/system/sshd.service.d && \
    printf '[Service]\nRuntimeDirectory=sshd\nRuntimeDirectoryMode=0755\n' \
      > /etc/systemd/system/sshd.service.d/runtime.conf && \
    (systemctl enable ssh.service || systemctl enable sshd.service) && \
    systemctl mask systemd-remount-fs.service getty@.service console-getty.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
