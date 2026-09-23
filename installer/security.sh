#!/usr/bin/env bash

ensure_service_identity() {
  getent group "$WANSIM_SERVICE_GROUP" >/dev/null || groupadd --system "$WANSIM_SERVICE_GROUP"
  if ! id "$WANSIM_SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --gid "$WANSIM_SERVICE_GROUP" --home-dir "$WANSIM_DATA_DIR" --shell /usr/sbin/nologin "$WANSIM_SERVICE_USER"
  fi
}

read_existing_env() {
  local name="$1" file="$WANSIM_ETC_DIR/wansim.env"
  [[ -r "$file" ]] || return 0
  sed -n "s/^${name}=\"\(.*\)\"$/\1/p" "$file" | tail -n 1
}

generate_fernet_key() {
  python3 - <<'PY'
import base64, os
print(base64.urlsafe_b64encode(os.urandom(32)).decode())
PY
}

normalize_tls_material() {
  local cert_dir="$WANSIM_ETC_DIR/certs"
  [[ "$WANSIM_HTTPS_MODE" == "off" ]] && return 0
  install -d -m 0750 -o root -g "$WANSIM_SERVICE_GROUP" "$cert_dir"
  case "$WANSIM_HTTPS_MODE" in
    self-signed)
      if [[ ! -s "$cert_dir/fullchain.pem" || ! -s "$cert_dir/privkey.pem" ]]; then
        openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
          -subj "/CN=$(hostname -f 2>/dev/null || hostname)" \
          -addext "subjectAltName=DNS:$(hostname -f 2>/dev/null || hostname),IP:127.0.0.1" \
          -keyout "$cert_dir/privkey.pem" -out "$cert_dir/fullchain.pem"
      fi
      ;;
    pem)
      if [[ -n "$WANSIM_TLS_CERT" || -n "$WANSIM_TLS_KEY" ]]; then
        [[ -r "$WANSIM_TLS_CERT" && -r "$WANSIM_TLS_KEY" ]] || die "HTTPS PEM requiere --tls-cert y --tls-key legibles."
        install -m 0640 "$WANSIM_TLS_CERT" "$cert_dir/fullchain.pem"
        install -m 0640 "$WANSIM_TLS_KEY" "$cert_dir/privkey.pem"
      fi
      ;;
    pfx)
      if [[ -n "$WANSIM_TLS_CERT" ]]; then
        [[ -r "$WANSIM_TLS_CERT" ]] || die "HTTPS PFX requiere --tls-cert."
        openssl pkcs12 -in "$WANSIM_TLS_CERT" -clcerts -nokeys -out "$cert_dir/fullchain.pem" -passin "pass:$WANSIM_TLS_PASSWORD"
        openssl pkcs12 -in "$WANSIM_TLS_CERT" -nocerts -nodes -out "$cert_dir/privkey.pem" -passin "pass:$WANSIM_TLS_PASSWORD"
      fi
      ;;
    der)
      if [[ -n "$WANSIM_TLS_CERT" || -n "$WANSIM_TLS_KEY" ]]; then
        [[ -r "$WANSIM_TLS_CERT" && -r "$WANSIM_TLS_KEY" ]] || die "HTTPS DER requiere --tls-cert y --tls-key."
        openssl x509 -inform DER -in "$WANSIM_TLS_CERT" -out "$cert_dir/fullchain.pem"
        openssl pkey -inform DER -in "$WANSIM_TLS_KEY" -out "$cert_dir/privkey.pem"
      fi
      ;;
  esac
  openssl x509 -in "$cert_dir/fullchain.pem" -noout -checkend 86400 >/dev/null || die "El certificado TLS no es válido por al menos 24 horas."
  openssl pkey -in "$cert_dir/privkey.pem" -noout >/dev/null || die "La clave privada TLS no es válida."
  local cert_public key_public
  cert_public="$(openssl x509 -in "$cert_dir/fullchain.pem" -pubkey -noout | openssl sha256)"
  key_public="$(openssl pkey -in "$cert_dir/privkey.pem" -pubout | openssl sha256)"
  [[ "$cert_public" == "$key_public" ]] || die "El certificado TLS y la clave privada no corresponden."
  chown root:"$WANSIM_SERVICE_GROUP" "$cert_dir/fullchain.pem" "$cert_dir/privkey.pem"
  chmod 0640 "$cert_dir/fullchain.pem" "$cert_dir/privkey.pem"
}

prepare_security_and_state() {
  ensure_service_identity
  install -d -m 0750 -o root -g "$WANSIM_SERVICE_GROUP" "$WANSIM_ETC_DIR" "$WANSIM_ETC_DIR/certs"
  install -d -m 0770 -o "$WANSIM_SERVICE_USER" -g "$WANSIM_SERVICE_GROUP" \
    "$WANSIM_DATA_DIR" "$WANSIM_DATA_DIR/active" "$WANSIM_DATA_DIR/drafts" "$WANSIM_DATA_DIR/snapshots"
  install -d -m 0750 -o "$WANSIM_SERVICE_USER" -g "$WANSIM_SERVICE_GROUP" "$WANSIM_LOG_DIR"

  local api_key secret_key agent_token existing
  existing="$(read_existing_env WANSIM_V2_API_KEY)"
  api_key="${WANSIM_ADMIN_KEY:-${existing:-$(openssl rand -base64 36 | tr -d '\n')}}"
  secret_key="$(read_existing_env WANSIM_V2_SECRET_KEY)"; secret_key="${secret_key:-$(generate_fernet_key)}"
  agent_token="$(read_existing_env WANSIM_V2_AGENT_TOKEN)"; agent_token="${agent_token:-$(openssl rand -hex 32)}"
  [[ ${#api_key} -ge 24 ]] || die "La clave de operador debe contener al menos 24 caracteres."

  local env_tmp
  env_tmp="$(mktemp "$WANSIM_ETC_DIR/.wansim.env.XXXXXX")"
  {
    printf 'WANSIM_V2_API_KEY=%s\n' "$(escape_env_value "$api_key")"
    printf 'WANSIM_V2_SECRET_KEY=%s\n' "$(escape_env_value "$secret_key")"
    printf 'WANSIM_V2_AGENT_TOKEN=%s\n' "$(escape_env_value "$agent_token")"
    printf 'WANSIM_V2_AGENT_SOCKET=%s\n' "$(escape_env_value "$WANSIM_RUN_DIR/agent.sock")"
    printf 'WANSIM_V2_DATA_DIR=%s\n' "$(escape_env_value "$WANSIM_DATA_DIR")"
    printf 'WANSIM_V2_EXECUTION_MODE=%s\n' "$(escape_env_value "$WANSIM_EXECUTION_MODE")"
    printf 'WANSIM_V2_ALLOW_HOST_APPLY=%s\n' "$(escape_env_value "$([[ "$WANSIM_EXECUTION_MODE" == host ]] && printf 1 || printf 0)")"
    printf 'WANSIM_BIND_ADDRESS=%s\n' "$(escape_env_value "$WANSIM_BIND_ADDRESS")"
    printf 'WANSIM_HTTP_PORT=%s\n' "$(escape_env_value "$WANSIM_HTTP_PORT")"
    printf 'WANSIM_HTTPS_PORT=%s\n' "$(escape_env_value "$WANSIM_HTTPS_PORT")"
    printf 'WANSIM_HTTPS_MODE=%s\n' "$(escape_env_value "$WANSIM_HTTPS_MODE")"
    printf 'WANSIM_TLS_DIR=%s\n' "$(escape_env_value "$WANSIM_ETC_DIR/certs")"
    printf 'WANSIM_GID=%s\n' "$(escape_env_value "$(getent group "$WANSIM_SERVICE_GROUP" | cut -d: -f3)")"
  } > "$env_tmp"
  chown root:"$WANSIM_SERVICE_GROUP" "$env_tmp"
  chmod 0640 "$env_tmp"
  mv -f "$env_tmp" "$WANSIM_ETC_DIR/wansim.env"

  local config_tmp
  config_tmp="$(mktemp "$WANSIM_ETC_DIR/.config.yaml.XXXXXX")"
  {
    printf 'schemaVersion: 1\n'
    printf 'executionMode: %s\n' "$WANSIM_EXECUTION_MODE"
    printf 'bindAddress: "%s"\n' "$WANSIM_BIND_ADDRESS"
    printf 'httpPort: %s\n' "$WANSIM_HTTP_PORT"
    printf 'httpsMode: %s\n' "$WANSIM_HTTPS_MODE"
    printf 'httpsPort: %s\n' "$WANSIM_HTTPS_PORT"
  } > "$config_tmp"
  chown root:"$WANSIM_SERVICE_GROUP" "$config_tmp"
  chmod 0640 "$config_tmp"
  mv -f "$config_tmp" "$WANSIM_ETC_DIR/config.yaml"

  normalize_tls_material
  log_ok "Identidad, secretos, certificados y directorios persistentes preparados."
  log_warn "La clave de operador está en $WANSIM_ETC_DIR/wansim.env (modo 0640); no se imprime en consola."
}
