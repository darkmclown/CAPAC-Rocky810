#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap Validator
# File: bootstrap/validate.sh
#
# Purpose:
#   Standalone validation script.
#   Does not install or modify major system configuration.
#
# Checks:
#   - Root access
#   - Rocky Linux version
#   - Repo structure
#   - Module discovery
#   - Module function contracts
#   - Basic services
#   - Network/time sanity
#   - Slurm/Munge presence if installed
# ==============================================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODULE_DIR="${ROOT_DIR}/modules"

LOG_DIR="${LOG_DIR:-/var/log/capac-bootstrap}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/validate.log}"

STATE_DIR="${STATE_DIR:-/var/lib/capac-bootstrap}"
BOOTSTRAP_STATE_FILE="${STATE_DIR}/bootstrap.state"
FAILED_FILE="${STATE_DIR}/failed.module"

MODULES=()

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

prepare_logging() {
  mkdir -p "${LOG_DIR}"
  touch "${LOG_FILE}"
  chmod 0644 "${LOG_FILE}"
}

log() {
  echo -e "$*" | tee -a "${LOG_FILE}"
}

log_info() {
  log "\033[1;34m[INFO]\033[0m $*"
}

log_ok() {
  log "\033[1;32m[ OK ]\033[0m $*"
}

log_warn() {
  log "\033[1;33m[WARN]\033[0m $*"
}

log_error() {
  log "\033[1;31m[ERROR]\033[0m $*"
}

log_section() {
  log ""
  log "\033[1;36m============================================================\033[0m"
  log "\033[1;36m$*\033[0m"
  log "\033[1;36m============================================================\033[0m"
}

# ------------------------------------------------------------------------------
# Fail-safe
# ------------------------------------------------------------------------------

fail_safe_exit() {
  local exit_code="$?"
  local line_no="${BASH_LINENO[0]:-unknown}"
  local command="${BASH_COMMAND:-unknown}"

  if [[ "${exit_code}" -ne 0 ]]; then
    log_error "Validation failed unexpectedly."
    log_error "Exit code : ${exit_code}"
    log_error "Line      : ${line_no}"
    log_error "Command   : ${command}"
    log_error "Log file  : ${LOG_FILE}"
  fi
}

trap fail_safe_exit EXIT

# ------------------------------------------------------------------------------
# Utility Checks
# ------------------------------------------------------------------------------

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] This validator must be run as root or with sudo."
    exit 1
  fi
}

check_file() {
  local file="$1"

  if [[ -f "${file}" ]]; then
    log_ok "File exists: ${file}"
    return 0
  else
    log_warn "File missing: ${file}"
    return 1
  fi
}

check_dir() {
  local dir="$1"

  if [[ -d "${dir}" ]]; then
    log_ok "Directory exists: ${dir}"
    return 0
  else
    log_warn "Directory missing: ${dir}"
    return 1
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

check_service() {
  local svc="$1"

  if ! systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    log_warn "Service unit not found: ${svc}"
    return 1
  fi

  if systemctl is-enabled "${svc}" >/dev/null 2>&1; then
    log_ok "Service enabled: ${svc}"
  else
    log_warn "Service not enabled: ${svc}"
  fi

  if systemctl is-active "${svc}" >/dev/null 2>&1; then
    log_ok "Service active: ${svc}"
  else
    log_warn "Service not active: ${svc}"
  fi
}

# ------------------------------------------------------------------------------
# OS and Structure Validation
# ------------------------------------------------------------------------------

validate_os() {
  log_section "Validating Operating System"

  if [[ -f /etc/rocky-release ]]; then
    local os_release
    os_release="$(cat /etc/rocky-release)"
    log_info "Detected OS: ${os_release}"

    if echo "${os_release}" | grep -q "Rocky Linux release 8.10"; then
      log_ok "Rocky Linux 8.10 detected."
    else
      log_warn "Rocky Linux detected, but not confirmed as 8.10."
    fi
  else
    log_warn "/etc/rocky-release not found."
    log_warn "This system may not be Rocky Linux."
  fi

  if [[ -f /etc/os-release ]]; then
    log_info "os-release summary:"
    grep -E "^(NAME|VERSION|ID|VERSION_ID)=" /etc/os-release | tee -a "${LOG_FILE}" || true
  fi

  log_info "Kernel: $(uname -r)"
  log_info "Architecture: $(uname -m)"
}

validate_structure() {
  log_section "Validating Repository Structure"

  log_info "Script name    : ${SCRIPT_NAME}"
  log_info "Root directory : ${ROOT_DIR}"
  log_info "Bootstrap dir  : ${SCRIPT_DIR}"
  log_info "Modules dir    : ${MODULE_DIR}"
  log_info "Log file       : ${LOG_FILE}"

  check_dir "${ROOT_DIR}"
  check_dir "${SCRIPT_DIR}"
  check_dir "${MODULE_DIR}"

  check_file "${SCRIPT_DIR}/bootstrap.sh"
  check_file "${SCRIPT_DIR}/loader.sh"
  check_file "${SCRIPT_DIR}/validate.sh"

  if [[ -f "${SCRIPT_DIR}/bootstrap.sh" ]]; then
    if bash -n "${SCRIPT_DIR}/bootstrap.sh"; then
      log_ok "Syntax OK: bootstrap.sh"
    else
      log_error "Syntax error: bootstrap.sh"
    fi
  fi

  if [[ -f "${SCRIPT_DIR}/loader.sh" ]]; then
    if bash -n "${SCRIPT_DIR}/loader.sh"; then
      log_ok "Syntax OK: loader.sh"
    else
      log_error "Syntax error: loader.sh"
    fi
  fi
}

# ------------------------------------------------------------------------------
# Module Discovery and Contract Validation
# ------------------------------------------------------------------------------

discover_modules() {
  log_section "Discovering Modules"

  MODULES=()

  shopt -s nullglob

  local module_path
  for module_path in "${MODULE_DIR}"/*.sh; do
    local module_name
    module_name="$(basename "${module_path}")"

    if [[ "${module_name}" == "common.sh" ]]; then
      log_info "Skipping shared helper: ${module_name}"
      continue
    fi

    MODULES+=("${module_name}")
  done

  shopt -u nullglob

  if [[ "${#MODULES[@]}" -eq 0 ]]; then
    log_warn "No executable modules found in ${MODULE_DIR}"
    return 1
  fi

  mapfile -t MODULES < <(printf "%s\n" "${MODULES[@]}" | sort)

  log_info "Discovered modules:"

  local module
  for module in "${MODULES[@]}"; do
    log_ok "${module}"
  done
}

get_module_function_name() {
  local module="$1"
  local base_name

  base_name="$(basename "${module}" .sh)"

  # Supports numeric ordering:
  # 010-packages.sh -> packages_main
  # 020-NTP.sh      -> NTP_main
  base_name="$(echo "${base_name}" | sed -E 's/^[0-9]+[-_]?//')"

  # Convert unsafe characters to underscore.
  base_name="$(echo "${base_name}" | sed -E 's/[^a-zA-Z0-9_]/_/g')"

  echo "${base_name}_main"
}

validate_modules() {
  log_section "Validating Module Contracts"

  local module

  for module in "${MODULES[@]}"; do
    local module_path="${MODULE_DIR}/${module}"
    local module_function

    module_function="$(get_module_function_name "${module}")"

    log_info "Checking module: ${module}"
    log_info "Expected function: ${module_function}()"

    if ! bash -n "${module_path}"; then
      log_error "Syntax error in module: ${module}"
      continue
    fi

    # shellcheck source=/dev/null
    source "${module_path}"

    if declare -F "${module_function}" >/dev/null 2>&1; then
      log_ok "${module} exposes ${module_function}()"
    else
      log_error "${module} is missing required function: ${module_function}()"
    fi
  done
}

# ------------------------------------------------------------------------------
# System Health Validation
# ------------------------------------------------------------------------------

validate_basic_commands() {
  log_section "Validating Basic Commands"

  check_command bash
  check_command dnf
  check_command git
  check_command curl
  check_command hostname
  check_command systemctl
  check_command timedatectl
  check_command ip
  check_command ss
  check_command awk
  check_command sed
}

validate_time() {
  log_section "Validating Time and NTP"

  timedatectl status | tee -a "${LOG_FILE}" || true

  check_command chronyc

  if command -v chronyc >/dev/null 2>&1; then
    chronyc tracking | tee -a "${LOG_FILE}" || true
    chronyc sources -v | tee -a "${LOG_FILE}" || true
  fi

  check_service chronyd
}

validate_network() {
  log_section "Validating Network"

  log_info "Hostname short : $(hostname -s 2>/dev/null || hostname)"
  log_info "Hostname FQDN  : $(hostname -f 2>/dev/null || echo 'FQDN not configured')"

  log_info "IP addresses:"
  ip -brief addr | tee -a "${LOG_FILE}" || true

  log_info "Routes:"
  ip route | tee -a "${LOG_FILE}" || true

  log_info "Listening TCP ports:"
  ss -tulpen | tee -a "${LOG_FILE}" || true
}

validate_hpc_services() {
  log_section "Validating HPC Services"

  check_command munge
  check_command slurmctld
  check_command slurmd
  check_command sinfo
  check_command scontrol

  check_service munge
  check_service slurmctld
  check_service slurmd

  if command -v scontrol >/dev/null 2>&1; then
    log_info "Slurm controller ping:"
    scontrol ping | tee -a "${LOG_FILE}" || true
  fi

  if command -v sinfo >/dev/null 2>&1; then
    log_info "Slurm node/partition status:"
    sinfo | tee -a "${LOG_FILE}" || true
  fi
}

validate_monitoring() {
  log_section "Validating Monitoring Tools"

  check_command sar
  check_command iostat
  check_command vmstat
  check_command nmon
  check_command glances
  check_command prometheus-node-exporter

  check_service sysstat
  check_service prometheus-node-exporter
}

validate_state() {
  log_section "Validating Bootstrap State"

  if [[ -f "${BOOTSTRAP_STATE_FILE}" ]]; then
    log_info "Bootstrap state file: ${BOOTSTRAP_STATE_FILE}"
    cat "${BOOTSTRAP_STATE_FILE}" | tee -a "${LOG_FILE}" || true
  else
    log_warn "Bootstrap state file not found: ${BOOTSTRAP_STATE_FILE}"
  fi

  if [[ -f "${FAILED_FILE}" ]]; then
    log_warn "Failed module file exists: ${FAILED_FILE}"
    cat "${FAILED_FILE}" | tee -a "${LOG_FILE}" || true
  else
    log_ok "No failed module marker found."
  fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
  require_root
  prepare_logging

  log_section "CAPAC Rocky 8.10 CAE/HPC Bootstrap Validation Started"

  validate_os
  validate_structure
  discover_modules || true
  validate_modules || true

  validate_basic_commands
  validate_time
  validate_network
  validate_hpc_services
  validate_monitoring
  validate_state

  log_section "Validation Completed"
  log_info "Validation log: ${LOG_FILE}"
}

main "$@"