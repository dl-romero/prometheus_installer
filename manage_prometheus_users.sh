#!/bin/bash
set -euo pipefail

WEB_CONFIG="/etc/prometheus/web.yml"
ACTION="${1:-}"
USERNAME="${2:-}"
PASSWORD_ARG="${3:-}"
DO_RELOAD=0

for arg in "$@"; do
  if [[ "${arg}" == "--reload" ]]; then
    DO_RELOAD=1
  fi
done

usage() {
  cat <<EOF
Usage:
  $0 add <username> [password] [--reload]
  $0 remove <username> [--reload]
  $0 update <username> [password] [--reload]
  $0 list

Notes:
  - Edits ${WEB_CONFIG} basic_auth_users section.
  - Run as root.
  - If [password] is omitted for add/update, you will be prompted securely.
  - --reload will run: systemctl reload prometheus
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root (sudo)."
    exit 1
  fi
}

require_htpasswd() {
  if command -v htpasswd >/dev/null 2>&1; then
    return
  fi

  echo "htpasswd not found. Installing httpd-tools..."
  yum install -y httpd-tools

  if ! command -v htpasswd >/dev/null 2>&1; then
    echo "Unable to install htpasswd. Please install httpd-tools and retry."
    exit 1
  fi
}

prompt_password() {
  local p1=""
  local p2=""

  read -r -s -p "Password for ${USERNAME}: " p1
  echo
  read -r -s -p "Confirm password: " p2
  echo

  if [[ "${p1}" != "${p2}" ]]; then
    echo "Passwords do not match."
    exit 1
  fi

  if [[ -z "${p1}" ]]; then
    echo "Password cannot be empty."
    exit 1
  fi

  PASSWORD_ARG="${p1}"
}

generate_hash() {
  printf '%s\n' "${PASSWORD_ARG}" | htpasswd -niBC 12 "${USERNAME}" | cut -d: -f2
}

declare -A USER_HASHES=()

load_users() {
  local in_section=0
  local line=""

  if [[ ! -f "${WEB_CONFIG}" ]]; then
    return
  fi

  while IFS= read -r line; do
    if [[ "${line}" =~ ^basic_auth_users:[[:space:]]*$ ]]; then
      in_section=1
      continue
    fi

    if [[ "${line}" =~ ^basic_auth_users:[[:space:]]*\{\}[[:space:]]*$ ]]; then
      in_section=0
      continue
    fi

    if [[ "${in_section}" -eq 1 ]]; then
      if [[ "${line}" =~ ^[[:space:]]{2}([^:[:space:]][^:]*):[[:space:]]*(.+)[[:space:]]*$ ]]; then
        USER_HASHES["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
      elif [[ "${line}" =~ ^[^[:space:]] ]]; then
        in_section=0
      fi
    fi
  done <"${WEB_CONFIG}"
}

write_users() {
  local users=()
  local user=""

  users=("${!USER_HASHES[@]}")
  IFS=$'\n' users=($(printf '%s\n' "${users[@]}" | sort))

  if [[ "${#users[@]}" -eq 0 ]]; then
    cat >"${WEB_CONFIG}" <<EOF
basic_auth_users: {}
EOF
  else
    {
      echo "basic_auth_users:"
      for user in "${users[@]}"; do
        echo "  ${user}: ${USER_HASHES[${user}]}"
      done
    } >"${WEB_CONFIG}"
  fi

  chmod 640 "${WEB_CONFIG}"
  if id prometheus >/dev/null 2>&1; then
    chown prometheus:prometheus "${WEB_CONFIG}"
  fi
}

if [[ -z "${ACTION}" ]]; then
  usage
  exit 1
fi

case "${ACTION}" in
  add|remove|update)
    if [[ -z "${USERNAME}" ]]; then
      echo "Username is required for ${ACTION}."
      usage
      exit 1
    fi
    ;;
  list)
    ;;
  help|--help|-h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown action: ${ACTION}"
    usage
    exit 1
    ;;
esac

require_root
load_users

reload_prometheus_if_requested() {
  if [[ "${DO_RELOAD}" -eq 1 ]]; then
    if systemctl reload prometheus; then
      echo "Prometheus reloaded."
    else
      echo "Failed to reload Prometheus service."
      exit 1
    fi
  fi
}

case "${ACTION}" in
  add)
    if [[ "${PASSWORD_ARG}" == "--reload" ]]; then
      PASSWORD_ARG=""
    fi

    if [[ -n "${USER_HASHES[${USERNAME}]:-}" ]]; then
      echo "User '${USERNAME}' already exists. Use update instead."
      exit 1
    fi

    if [[ -z "${PASSWORD_ARG}" ]]; then
      prompt_password
    fi

    require_htpasswd
    USER_HASHES["${USERNAME}"]="$(generate_hash)"
    write_users
    echo "Added user '${USERNAME}' to ${WEB_CONFIG}."
    reload_prometheus_if_requested
    ;;

  update)
    if [[ "${PASSWORD_ARG}" == "--reload" ]]; then
      PASSWORD_ARG=""
    fi

    if [[ -z "${USER_HASHES[${USERNAME}]:-}" ]]; then
      echo "User '${USERNAME}' does not exist. Use add instead."
      exit 1
    fi

    if [[ -z "${PASSWORD_ARG}" ]]; then
      prompt_password
    fi

    require_htpasswd
    USER_HASHES["${USERNAME}"]="$(generate_hash)"
    write_users
    echo "Updated user '${USERNAME}' in ${WEB_CONFIG}."
    reload_prometheus_if_requested
    ;;

  remove)
    if [[ -z "${USER_HASHES[${USERNAME}]:-}" ]]; then
      echo "User '${USERNAME}' does not exist."
      exit 1
    fi

    unset USER_HASHES["${USERNAME}"]
    write_users
    echo "Removed user '${USERNAME}' from ${WEB_CONFIG}."
    reload_prometheus_if_requested
    ;;

  list)
    if [[ "${#USER_HASHES[@]}" -eq 0 ]]; then
      echo "No users found in ${WEB_CONFIG}."
      exit 0
    fi

    echo "Users in ${WEB_CONFIG}:"
    printf '%s\n' "${!USER_HASHES[@]}" | sort
    ;;
esac
