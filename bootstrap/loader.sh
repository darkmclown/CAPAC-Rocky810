#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap Loader
# File: bootstrap/loader.sh
#
# Purpose:
#   Curl/GitHub entrypoint.
#   - Installs minimal prerequisites
#   - Clones or updates repo
#   - Validates scripts
#   - Waits for user input
#   - Starts bootstrap in automated/manual/validation mode
# ==============================================================================

REPO_URL="${REPO_URL:-https://github.com/darkmclown/CAPAC-Rocky810.git}"
BRANCH="${BRANCH:-main}"
WORKDIR="${WORKDIR:-/opt/CAPAC-Rocky810}"

LOG_DIR="${LOG_DIR:-/var/log/capac-bootstrap}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/loader.log}"

BOOTSTRAP_SCRIPT="${WORKDIR}/bootstrap/bootstrap.sh"
VALIDATE_SCRIPT="${WORKDIR}/bootstrap/validate.sh"

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
# Safe Input
# ------------------------------------------------------------------------------

read_tty() {
  local prompt="$1"
  local var_name="$2"

  if [[ -r /dev/tty ]]; then
    read -rp "${prompt}" "${var_name}" < /dev/tty
  else
    log_error "No interactive terminal available."
    log_error "Run this command from an interactive shell."
    exit 1
  fi
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

  dnf install -y git curl ca-certificates

  log_ok "Loader prerequisites are ready."
}

show_loader_config() {
  log_section "Loader Configuration"

  log_info "Repository URL : ${REPO_URL}"
  log_info "Branch         : ${BRANCH}"
  log_info "Work directory : ${WORKDIR}"
  log_info "Log file       : ${LOG_FILE}"
}

clone_or_update_repo() {
  log_section "Preparing Bootstrap Repository"

  mkdir -p "$(dirname "${WORKDIR}")"

  if [[ -d "${WORKDIR}/.git" ]]; then
    log_info "Existing repository found at ${WORKDIR}"
    log_info "Updating repository..."

    git -C "${WORKDIR}" fetch --all --prune
    git -C "${WORKDIR}" checkout "${BRANCH}"
    git -C "${WORKDIR}" pull --ff-only origin "${BRANCH}"
  else
    if [[ -d "${WORKDIR}" && -n "$(ls -A "${WORKDIR}" 2>/dev/null)" ]]; then
      local backup_dir
      backup_dir="${WORKDIR}.backup.$(date +%Y%m%d%H%M%S)"

      log_warn "Work directory exists and is not empty."
      log_warn "Moving old directory to: ${backup_dir}"

      mv "${WORKDIR}" "${backup_dir}"
    fi

    log_info "Cloning repository..."
    git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${WORKDIR}"
  fi

  chmod +x "${WORKDIR}/bootstrap/"*.sh 2>/dev/null || true
  chmod +x "${WORKDIR}/modules/"*.sh 2>/dev/null || true

  log_ok "Repository is ready."
}

validate_scripts() {
  log_section "Validating Bootstrap Scripts"

  if [[ ! -f "${BOOTSTRAP_SCRIPT}" ]]; then
    log_error "Missing bootstrap script: ${BOOTSTRAP_SCRIPT}"
    exit 1
  fi

  if [[ ! -f "${VALIDATE_SCRIPT}" ]]; then
    log_error "Missing validate script: ${VALIDATE_SCRIPT}"
    exit 1
  fi

  bash -n "${BOOTSTRAP_SCRIPT}"
  bash -n "${VALIDATE_SCRIPT}"

  log_ok "bootstrap.sh syntax OK."
  log_ok "validate.sh syntax OK."
}

loader_menu() {
  log_section "Bootstrap Loader Menu"

  echo ""
  echo "Repository is ready at:"
  echo "  ${WORKDIR}"
  echo ""
  echo "Select action:"
  echo ""
  echo "  1) Module installation"
  echo "     Choose automated or manual module execution."
  echo ""
  echo "  2) Standalone validation only"
  echo "     Runs validate.sh without installing or changing packages."
  echo ""
  echo "  3) Exit"
  echo "     Repo is cloned/updated, but nothing else will run."
  echo ""

  local loader_choice

  while true; do
    read_tty "Enter choice [1/2/3]: " loader_choice

    case "${loader_choice}" in
      1)
        module_install_menu
        ;;
      2)
        log_info "Running standalone validation only..."
        exec bash "${VALIDATE_SCRIPT}"
        ;;
      3)
        log_info "Exiting loader. No bootstrap process started."
        log_info "You can start later with:"
        log_info "  sudo bash ${BOOTSTRAP_SCRIPT}"
        exit 0
        ;;
      *)
        echo "Invalid choice. Please enter 1, 2, or 3."
        ;;
    esac
  done
}

module_install_menu() {
  log_section "Module Installation Menu"

  echo ""
  echo "Choose module installation mode:"
  echo ""
  echo "  1) Automated module installation"
  echo "     Runs all discovered modules in sorted order."
  echo ""
  echo "  2) Manual module selection"
  echo "     Lets you select one module/script at a time."
  echo ""
  echo "  3) Bootstrap validation only"
  echo "     Validates OS, structure, and module contracts."
  echo ""
  echo "  4) Back to loader menu"
  echo ""
  echo "  5) Exit"
  echo ""

  local install_choice

  while true; do
    read_tty "Enter choice [1/2/3/4/5]: " install_choice

    case "${install_choice}" in
      1)
        log_info "Starting bootstrap in automated mode..."
        exec bash "${BOOTSTRAP_SCRIPT}" --auto
        ;;
      2)
        log_info "Starting bootstrap in manual mode..."
        exec bash "${BOOTSTRAP_SCRIPT}" --manual
        ;;
      3)
        log_info "Starting bootstrap validation mode..."
        exec bash "${BOOTSTRAP_SCRIPT}" --validate
        ;;
      4)
        loader_menu
        ;;
      5)
        log_info "Exiting loader."
        exit 0
        ;;
      *)
        echo "Invalid choice. Please enter 1, 2, 3, 4, or 5."
        ;;
    esac
  done
}

main() {
  require_root
  prepare_logging

  log_section "CAPAC Rocky 8.10 CAE/HPC Bootstrap Loader Started"

  install_prerequisites
  show_loader_config
  clone_or_update_repo
  validate_scripts
  loader_menu
}

main "$@"