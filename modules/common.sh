#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/common.sh
#
# Purpose:
#   Shared helper functions used by bootstrap modules.
#   This file is sourced by bootstrap.sh and skipped during module execution.
# ==============================================================================

backup_file() {
  local file="$1"

  if [[ -f "${file}" ]]; then
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "${file}" "${backup}"
    log_ok "Backup created: ${backup}"
  else
    log_warn "File not found, backup skipped: ${file}"
  fi
}

run_cmd() {
  log_info "Running: $*"
  "$@"
}

install_packages() {
  local packages=("$@")

  if [[ "${#packages[@]}" -eq 0 ]]; then
    log_warn "No packages provided to install_packages."
    return 0
  fi

  log_info "Installing packages: ${packages[*]}"
  dnf install -y "${packages[@]}"
}

enable_service() {
  local service="$1"

  if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
    systemctl enable --now "${service}" || {
      log_warn "Could not enable/start service: ${service}"
      return 1
    }

    log_ok "Service enabled and started: ${service}"
  else
    log_warn "Service unit not found: ${service}"
  fi
}

enable_service_only() {
  local service="$1"

  if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
    systemctl enable "${service}" || {
      log_warn "Could not enable service: ${service}"
      return 1
    }

    log_ok "Service enabled: ${service}"
  else
    log_warn "Service unit not found: ${service}"
  fi
}

check_command() {
  local cmd="$1"

  if command -v "${cmd}" >/dev/null 2>&1; then
    log_ok "Command available: ${cmd}"
    return 0
  else
    log_warn "Command missing: ${cmd}"
    return 1
  fi
}

check_service_status() {
  local service="$1"

  if systemctl is-active "${service}" >/dev/null 2>&1; then
    log_ok "Service active: ${service}"
  else
    log_warn "Service not active: ${service}"
  fi
}

create_dir() {
  local dir="$1"
  local owner="${2:-root:root}"
  local mode="${3:-0755}"

  mkdir -p "${dir}"
  chown "${owner}" "${dir}" || true
  chmod "${mode}" "${dir}" || true

  log_ok "Directory ready: ${dir}"
}

append_if_missing() {
  local line="$1"
  local file="$2"

  touch "${file}"

  if grep -Fxq "${line}" "${file}"; then
    log_info "Line already present in ${file}: ${line}"
  else
    echo "${line}" >> "${file}"
    log_ok "Added line to ${file}: ${line}"
  fi
}