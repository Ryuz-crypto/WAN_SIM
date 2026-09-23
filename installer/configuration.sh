#!/usr/bin/env bash

strip_yaml_value() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$value"
}

read_secret_file() {
  local path="$1" label="$2"
  [[ -r "$path" ]] || die "$label no es legible: $path"
  local value
  value="$(tr -d '\r\n' < "$path")"
  [[ -n "$value" ]] || die "$label está vacío: $path"
  printf '%s' "$value"
}

load_answer_file() {
  local file="$1" raw key value line=0
  [[ -r "$file" ]] || die "No se puede leer el archivo de respuestas: $file"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    ((line+=1))
    [[ "$raw" =~ ^[[:space:]]*$ || "$raw" =~ ^[[:space:]]*# ]] && continue
    [[ "$raw" == *:* ]] || die "YAML no válido en $file:$line; se requiere clave: valor."
    key="$(strip_yaml_value "${raw%%:*}")"
    value="$(strip_yaml_value "${raw#*:}")"
    case "$key" in
      bindAddress) WANSIM_BIND_ADDRESS="$value" ;;
      httpPort) WANSIM_HTTP_PORT="$value" ;;
      httpsMode) WANSIM_HTTPS_MODE="$value" ;;
      httpsPort) WANSIM_HTTPS_PORT="$value" ;;
      tlsCert) WANSIM_TLS_CERT="$value" ;;
      tlsKey) WANSIM_TLS_KEY="$value" ;;
      tlsPasswordFile) WANSIM_TLS_PASSWORD="$(read_secret_file "$value" tlsPasswordFile)" ;;
      adminKeyFile) WANSIM_ADMIN_KEY="$(read_secret_file "$value" adminKeyFile)" ;;
      executionMode) WANSIM_EXECUTION_MODE="$value" ;;
      confirmHostApply) WANSIM_CONFIRM_HOST_APPLY="$(boolean_value "$value")" ;;
      configureFirewall) WANSIM_CONFIGURE_FIREWALL="$(boolean_value "$value")" ;;
      skipConnectivityCheck) WANSIM_SKIP_CONNECTIVITY="$(boolean_value "$value")" ;;
      nonInteractive) WANSIM_NON_INTERACTIVE="$(boolean_value "$value")" ;;
      *) die "Clave YAML no soportada en $file:$line: $key" ;;
    esac
  done < "$file"
  WANSIM_ANSWER_FILE="$file"
  log_ok "Archivo de respuestas cargado: $file"
}

preload_answer_file() {
  local previous="" argument
  for argument in "$@"; do
    if [[ "$previous" == "--config" ]]; then
      load_answer_file "$argument"
      return
    fi
    previous="$argument"
  done
}
