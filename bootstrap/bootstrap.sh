#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: bootstrap/bootstrap.sh
#
# Purpose:
#   Master bootstrap controller.
#   Automatically discovers modules from ../modules/*.sh
#
# Modes:
#   1. Automated bootstrap
#   2. Manual module selection
#   3. Validation only
# ==============================================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODULE_DIR="${ROOT_DIR}/modules"

LOG_DIR="/var/log/capac-bootstrap"
LOG_FILE="${LOG_DIR}/bootstrap.log"

STATE_DIR="/var/lib/capac-bootstrap"
STATE_FILE="${STATE_DIR}/bootstrap.state"
FAILED_FILE="${STATE_DIR}/failed.module"

CLUSTER_NAME="${CLUSTER_NAME:-capac-hpc}"
NODE_ROLE="${NODE_ROLE:-master}"
TIMEZONE="${TIMEZONE:-Asia/Kolkata}"

# Discovered modules will be loaded here.
MODULES=()

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

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
    log_error "Bootstrap failed."
    log_error "Exit code : ${exit_code}"
    log_error "Line      : ${line_no}"
    log_error "Command   : ${command}"
    log_error "Log file  : ${LOG_FILE}"

    echo "FAILED" > "${STATE_FILE}" || true

    log_warn "Fail-safe triggered. System state preserved."
    log_warn "Last failed module, if any: ${FAILED_FILE}"
    log_warn "Re-run after fixing the issue:"
    log_warn "  sudo bash ${SCRIPT_DIR}/bootstrap.sh"
  fi
}

trap fail_safe_exit EXIT

# ------------------------------------------------------------------------------
# Basic Checks
# ------------------------------------------------------------------------------

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root or with sudo."
    exit 1
  fi
}

prepare_directories() {
  mkdir -p "${LOG_DIR}"
  mkdir -p "${STATE_DIR}"

  touch "${LOG_FILE}"
  touch "${STATE_FILE}"

  chmod 0644 "${LOG_FILE}"
  chmod 0644 "${STATE_FILE}"
}

validate_rocky() {
  log_section "Validating Operating System"

  if [[ ! -f /etc/rocky-release ]]; then
    log_error "This bootstrap is designed for Rocky Linux 8.10."
    log_error "Detected non-Rocky Linux system."
    exit 1
  fi

  local os_release
  os_release="$(cat /etc/rocky-release)"

  log_info "Detected OS: ${os_release}"

  if echo "${os_release}" | grep -q "Rocky Linux release 8.10"; then
    log_ok "Rocky Linux 8.10 validated."
  else
    log_warn "Expected Rocky Linux 8.10."
    log_warn "Current system: ${os_release}"

    read -rp "Continue anyway? [y/N]: " confirm
    case "${confirm}" in
      y|Y|yes|YES)
        log_warn "Continuing on non-validated Rocky version."
        ;;
      *)
        log_error "User aborted due to OS version mismatch."
        exit 1
        ;;
    esac
  fi
}

validate_structure() {
  log_section "Validating Bootstrap Directory Structure"

  log_info "Script name    : ${SCRIPT_NAME}"
  log_info "Root directory : ${ROOT_DIR}"
  log_info "Bootstrap dir  : ${SCRIPT_DIR}"
  log_info "Modules dir    : ${MODULE_DIR}"
  log_info "Log file       : ${LOG_FILE}"
  log_info "State file     : ${STATE_FILE}"

  if [[ ! -d "${MODULE_DIR}" ]]; then
    log_error "Modules directory not found: ${MODULE_DIR}"
    exit 1
  fi
}

show_context() {
  log_section "Bootstrap Context"

  log_info "Cluster name : ${CLUSTER_NAME}"
  log_info "Node role    : ${NODE_ROLE}"
  log_info "Timezone     : ${TIMEZONE}"
  log_info "Hostname     : $(hostname -f 2>/dev/null || hostname)"
  log_info "Kernel       : $(uname -r)"
}

# ------------------------------------------------------------------------------
# Module Discovery
# ------------------------------------------------------------------------------

discover_modules() {
  log_section "Discovering Modules"

  MODULES=()

  shopt -s nullglob

  local module_path
  for module_path in "${MODULE_DIR}"/*.sh; do
    local module_name
    module_name="$(basename "${module_path}")"

    # common.sh is treated as shared library/helper file.
    # It is not executed as a bootstrap module.
    if [[ "${module_name}" == "common.sh" ]]; then
      log_info "Skipping shared helper: ${module_name}"
      continue
    fi

    MODULES+=("${module_name}")
  done

  shopt -u nullglob

  if [[ "${#MODULES[@]}" -eq 0 ]]; then
    log_error "No executable modules found in ${MODULE_DIR}"
    log_error "Expected files like: packages.sh, NTP.sh, ipv4.sh, slurm.sh"
    exit 1
  fi

  # Sort modules alphabetically for deterministic execution.
  # Later, we can support numeric prefixes like:
  # 010-packages.sh, 020-NTP.sh, 030-ipv4.sh
  mapfile -t MODULES < <(printf "%s\n" "${MODULES[@]}" | sort)

  log_info "Discovered modules in execution order:"

  local module
  for module in "${MODULES[@]}"; do
    log_ok "${module}"
  done
}

get_module_function_name() {
  local module="$1"
  local base_name

  base_name="$(basename "${module}" .sh)"

  # Sanitize filename into a bash-safe function prefix.
  # Examples:
  #   packages.sh       -> packages_main
  #   NTP.sh            -> NTP_main
  #   010-packages.sh   -> packages_main
  #   020-ipv4.sh       -> ipv4_main
  #
  # Removes leading numeric ordering prefixes.
  base_name="$(echo "${base_name}" | sed -E 's/^[0-9]+[-_]?//')"

  # Replace invalid function-name characters with underscore.
  base_name="$(echo "${base_name}" | sed -E 's/[^a-zA-Z0-9_]/_/g')"

  echo "${base_name}_main"
}

validate_module_contracts() {
  log_section "Validating Module Contracts"

  local module
  for module in "${MODULES[@]}"; do
    local module_path="${MODULE_DIR}/${module}"
    local module_function

    module_function="$(get_module_function_name "${module}")"

    log_info "Checking ${module} -> ${module_function}()"

    # Load module to inspect function.
    # shellcheck source=/dev/null
    source "${module_path}"

    if declare -F "${module_function}" >/dev/null 2>&1; then
      log_ok "${module} exposes ${module_function}()"
    else
      log_error "${module} does not expose required function: ${module_function}()"
      log_error "Fix module or rename function before running bootstrap."
      exit 1
    fi
  done
}

# ------------------------------------------------------------------------------
# Module Execution
# ------------------------------------------------------------------------------

run_module() {
  local module="$1"
  local module_path="${MODULE_DIR}/${module}"
  local module_function

  module_function="$(get_module_function_name "${module}")"

  log_section "Starting Module: ${module}"

  if [[ ! -f "${module_path}" ]]; then
    log_error "Module file not found: ${module_path}"
    echo "${module}" > "${FAILED_FILE}"
    return 1
  fi

  # shellcheck source=/dev/null
  source "${module_path}"

  if ! declare -F "${module_function}" >/dev/null 2>&1; then
    log_error "Expected function not found: ${module_function}"
    log_error "Module must define: ${module_function}()"
    echo "${module}" > "${FAILED_FILE}"
    return 1
  fi

  echo "RUNNING:${module}" > "${STATE_FILE}"

  if "${module_function}"; then
    log_ok "Module completed successfully: ${module}"
    echo "COMPLETED:${module}" >> "${STATE_FILE}"
    rm -f "${FAILED_FILE}"
    return 0
  else
    log_error "Module failed: ${module}"
    echo "${module}" > "${FAILED_FILE}"
    echo "FAILED:${module}" >> "${STATE_FILE}"
    return 1
  fi
}

run_automated_mode() {
  log_section "Automated Bootstrap Mode"

  log_info "The following modules will run in order:"

  local module
  for module in "${MODULES[@]}"; do
    log_info "  - ${module}"
  done

  echo ""
  read -rp "Proceed with automated bootstrap? [y/N]: " confirm

  case "${confirm}" in
    y|Y|yes|YES)
      log_info "Starting automated bootstrap."
      ;;
    *)
      log_warn "Automated bootstrap cancelled by user."
      return 0
      ;;
  esac

  echo "STARTED:AUTOMATED" > "${STATE_FILE}"

  for module in "${MODULES[@]}"; do
    if run_module "${module}"; then
      log_ok "Proceeding to next module."
    else
      log_error "Stopping automated bootstrap due to failure in module: ${module}"
      log_warn "Failed module recorded in: ${FAILED_FILE}"
      log_warn "Fix the issue and re-run manual mode to retry."
      return 1
    fi
  done

  echo "COMPLETED:AUTOMATED" > "${STATE_FILE}"

  log_section "Automated Bootstrap Completed Successfully"
  log_ok "All discovered modules completed."
}

run_manual_mode() {
  while true; do
    log_section "Manual Module Selection"

    echo "Select a module to run:"
    echo ""

    local index=1
    local module

    for module in "${MODULES[@]}"; do
      echo "  ${index}) ${module}"
      index=$((index + 1))
    done

    echo ""
    echo "  r) Retry last failed module"
    echo "  l) List discovered modules"
    echo "  q) Quit"
    echo ""

    read -rp "Enter choice: " choice

    case "${choice}" in
      q|Q)
        log_info "Exiting manual mode."
        break
        ;;

      l|L)
        log_section "Discovered Modules"
        for module in "${MODULES[@]}"; do
          log_info "${module}"
        done
        ;;

      r|R)
        if [[ -f "${FAILED_FILE}" ]]; then
          local failed_module
          failed_module="$(cat "${FAILED_FILE}")"

          if [[ -n "${failed_module}" ]]; then
            log_info "Retrying failed module: ${failed_module}"
            run_module "${failed_module}" || true
          else
            log_warn "Failed module file is empty."
          fi
        else
          log_warn "No failed module found."
        fi
        ;;

      ''|*[!0-9]*)
        log_warn "Invalid selection."
        ;;

      *)
        local selected_index="${choice}"
        local module_position=$((selected_index - 1))

        if [[ "${module_position}" -ge 0 && "${module_position}" -lt "${#MODULES[@]}" ]]; then
          run_module "${MODULES[${module_position}]}" || true
        else
          log_warn "Invalid module number."
        fi
        ;;
    esac
  done
}

run_validation_only() {
  log_section "Bootstrap Validation Only"

  validate_rocky
  validate_structure
  discover_modules
  validate_module_contracts
  show_context

  log_ok "Validation completed successfully."
}

# ------------------------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------------------------

show_menu() {
  echo ""
  echo "============================================================"
  echo " CAPAC Rocky 8.10 CAE/HPC Bootstrap"
  echo "============================================================"
  echo ""
  echo " Select bootstrap mode:"
  echo ""
  echo "  1) Automated bootstrap"
  echo "     Discover and run all modules in sequence."
  echo ""
  echo "  2) Manual module selection"
  echo "     Select and run one discovered module at a time."
  echo ""
  echo "  3) Validation only"
  echo "     Validate OS, structure, discovered modules, and context."
  echo ""
  echo "  q) Quit"
  echo ""
}

main() {
  require_root
  prepare_directories

  log_section "CAPAC Rocky 8.10 CAE/HPC Bootstrap Started"

  validate_rocky
  validate_structure
  discover_modules
  validate_module_contracts
  show_context

  while true; do
    show_menu
    read -rp "Enter choice: " choice

    case "${choice}" in
      1)
        run_automated_mode
        break
        ;;
      2)
        run_manual_mode
        break
        ;;
      3)
        run_validation_only
        break
        ;;
      q|Q)
        log_info "Bootstrap exited by user."
        break
        ;;
      *)
        log_warn "Invalid choice. Please select 1, 2, 3, or q."
        ;;
    esac
  done

  log_section "Bootstrap Finished"
  log_info "Log file: ${LOG_FILE}"
  log_info "State file: ${STATE_FILE}"
}

main "$@"