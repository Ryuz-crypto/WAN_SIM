#!/usr/bin/env bash

docker_compose_ready() {
  command_exists docker && docker compose version >/dev/null 2>&1
}

install_docker_engine() {
  if docker_compose_ready; then
    log_ok "Docker Engine y Compose ya están disponibles."
  elif [[ "$WANSIM_OS_FAMILY" == "debian" ]]; then
    install_docker_debian
  else
    install_docker_rhel
  fi
  systemctl enable --now docker
  docker compose version >/dev/null 2>&1 || die "Docker Compose no quedó disponible."
  log_ok "Docker Engine y Compose listos."
}

install_docker_debian() {
  local repo_id="$WANSIM_DISTRO_ID"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${repo_id}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc
  local codename
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  [[ -n "$codename" ]] || die "No se pudo determinar VERSION_CODENAME para Docker."
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$repo_id" "$codename" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_rhel() {
  local repo_url
  if [[ "$WANSIM_DISTRO_ID" == "fedora" ]]; then
    repo_url=https://download.docker.com/linux/fedora/docker-ce.repo
  else
    repo_url=https://download.docker.com/linux/centos/docker-ce.repo
  fi
  curl -fsSL "$repo_url" -o /etc/yum.repos.d/docker-ce.repo
  dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}
