#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap Loader
# File: bootstrap/loader.sh
#
# Purpose:
#   GitHub/curl entrypoint.
#   Downloads or updates the bootstrap repository and invokes bootstrap.sh.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/CAPAC-Rocky810-bootstrap/main/bootstrap/loader.sh | sudo bash
#
# Optional overrides:
#   sudo REPO_URL="https://github.com/<org>/CAPAC-Rocky810-bootstrap.git" BRANCH="main" bash loader.sh
# ==============================================================================

REPO_URL="${REPO_URL:-https://github.com/<your-org>/CAPAC-Rocky810-bootstrap.git}"
BRANCH="${BRANCH:-main}"
WORKDIR="${WORKDIR:-/opt/CAPAC-Rocky810-bootstrap}"

LOG_DIR="${LOG_DIR:-/var/log/capac-bootstrap}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/loader.log}"

BOOTSTRAP_SCRIPT="${WORKDIR}/bootstrap/bootstrap.sh"

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
    log_error "Loader failed."
    log_error "Exit code : ${exit_code}"
    log_error "Line      : ${line_no}"
    log_error "Command   : ${command}"
    log_error "Log file  : ${LOG_FILE}"
  fi
}

trap fail_safe_exit EXIT

# ------------------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------------------

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] This loader must be run as root or with sudo."
    exit 1
  fi
}

install_prerequisites() {
  log_section "Checking Loader Prerequisites"

  if ! command -v dnf >/dev/null 2>&1; then
    log_error "dnf not found. This loader is intended for Rocky/RHEL compatible systems."
    exit 1
  fi

  local packages_to_install=()

  command -v git >/dev/null 2>&1 || packages_to_install+=("git")
  command -v curl >/dev/null 2>&1 || packages_to_install+=("curl")
  command -v ca-certificates >/dev/null 2>&1 || true

  if [[ "${#packages_to_install[@]}" -gt 0 ]]; then
    log_info "Installing required packages: ${packages_to_install[*]}"
    dnf install -y "${packages_to_install[@]}"
  else
    log_ok "Required tools are already available."
  fi
}

validate_repo_settings() {
  log_section "Loader Configuration"

  log_info "Repository URL : ${REPO_URL}"
  log_info "Branch         : ${BRANCH}"
  log_info "Work directory : ${WORKDIR}"
  log_info "Log file       : ${LOG_FILE}"

  if [[ "${REPO_URL}" == *"<your-org>"* ]]; then
    log_error "REPO_URL still contains placeholder <your-org>."
    log_error "Set your real GitHub repository URL before running:"
    log_error "  sudo REPO_URL=https://github.com/YOURORG/CAPAC-Rocky810-bootstrap.git bash loader.sh"
    exit 1
  fi
}

clone_or_update_repo() {
  log_section "Preparing Bootstrap Repository"

  mkdir -p "$(dirname "${WORKDIR}")"

  if [[ -d "${WORKDIR}/.git" ]]; then
    log_info "Existing Git repository found at ${WORKDIR}"
    log_info "Updating repository..."

    git -C "${WORKDIR}" fetch --all --prune
    git -C "${WORKDIR}" checkout "${BRANCH}"
    git -C "${WORKDIR}" pull --ff-only origin "${BRANCH}"
  else
    if [[ -d "${WORKDIR}" && -n "$(ls -A "${WORKDIR}" 2>/dev/null)" ]]; then
      log_warn "Work directory exists and is not empty: ${WORKDIR}"
      log_warn "Moving existing directory to backup."

      local backup_dir
      backup_dir="${WORKDIR}.backup.$(date +%Y%m%d%H%M%S)"
      mv "${WORKDIR}" "${backup_dir}"

      log_warn "Backup created: ${backup_dir}"
    fi

    log_info "Cloning repository..."
    git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${WORKDIR}"
  fi

  log_ok "Repository is ready."
}

validate_bootstrap_script() {
  log_section "Validating Bootstrap Entrypoint"

  if [[ ! -f "${BOOTSTRAP_SCRIPT}" ]]; then
    log_error "Bootstrap script not found: ${BOOTSTRAP_SCRIPT}"
    exit 1
  fi

  chmod +x "${WORKDIR}/bootstrap/"*.sh 2>/dev/null || true
  chmod +x "${WORKDIR}/modules/"*.sh 2>/dev/null || true

  if ! bash -n "${BOOTSTRAP_SCRIPT}"; then
    log_error "Syntax validation failed for ${BOOTSTRAP_SCRIPT}"
    exit 1
  fi

  log_ok "Bootstrap script validated: ${BOOTSTRAP_SCRIPT}"
}

invoke_bootstrap() {
  log_section "Invoking Bootstrap"

  log_info "Starting bootstrap controller..."
  exec bash "${BOOTSTRAP_SCRIPT}"
}

main() {
  require_root
  prepare_logging

  log_section "CAPAC Rocky 8.10 CAE/HPC Bootstrap Loader Started"

  install_prerequisites
  validate_repo_settings
  clone_or_update_repo
  validate_bootstrap_script
  invoke_bootstrap
}

main "$@"