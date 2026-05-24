#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/darkmclown/CAPAC-Rocky810.git}"
BRANCH="${BRANCH:-main}"
WORKDIR="${WORKDIR:-/opt/CAPAC-Rocky810}"

LOG_DIR="${LOG_DIR:-/var/log/capac-bootstrap}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/loader.log}"

BOOTSTRAP_SCRIPT="${WORKDIR}/bootstrap/bootstrap.sh"
VALIDATE_SCRIPT="${WORKDIR}/bootstrap/validate.sh"

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

invoke_bootstrap() {
  log_section "Bootstrap Loader Menu"

  echo ""
  echo "Repository is ready at:"
  echo "  ${WORKDIR}"
  echo ""
  echo "What do you want to do?"
  echo ""
  echo "  1) Start bootstrap menu"
  echo "     Opens bootstrap.sh and lets you choose automated/manual/validation."
  echo ""
  echo "  2) Run validation only"
  echo "     Runs validate.sh without installing or changing packages."
  echo ""
  echo "  3) Exit"
  echo "     Repo is cloned/updated, but nothing else will run."
  echo ""

  while true; do
    read -rp "Enter choice [1/2/3]: " loader_choice < /dev/tty

    case "${loader_choice}" in
      1)
        log_info "Starting bootstrap controller..."
        exec bash "${BOOTSTRAP_SCRIPT}"
        ;;

      2)
        log_info "Running validation only..."
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

main() {
  require_root
  prepare_logging

  log_section "CAPAC Rocky 8.10 CAE/HPC Bootstrap Loader Started"

  install_prerequisites
  show_loader_config
  clone_or_update_repo
  validate_scripts
  invoke_bootstrap
}

main "$@"