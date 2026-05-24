#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/020-vnc.sh
#
# Purpose:
#   Configure GUI/VNC/X11 environment for CAE and ANSYS applications.
#
# Behavior:
#   - Asks for VNC Linux user once
#   - Creates user if missing
#   - Asks for Linux password only when needed
#   - Asks for VNC password only when needed
#   - Remembers safe VNC settings in /etc/capac-bootstrap/vnc.conf
#   - Does NOT store plaintext passwords
#
# Required function:
#   vnc_main()
# ==============================================================================

vnc_main() {
  log_section "VNC / GUI / X11 Module for CAE and ANSYS"

  vnc_install_packages
  vnc_load_or_collect_settings
  vnc_validate_user
  vnc_prepare_user_config
  vnc_create_xstartup
  vnc_create_systemd_service
  vnc_enable_service
  vnc_save_settings
  vnc_summary

  log_ok "VNC / GUI / X11 module completed successfully."
}

# ------------------------------------------------------------------------------
# Package Installation
# ------------------------------------------------------------------------------

vnc_install_packages() {
  log_section "Installing VNC, XFCE, and X11 Packages"

  log_info "Installing XFCE desktop group if available..."

  dnf groupinstall -y "Xfce" || \
  dnf groupinstall -y "Xfce Desktop" || {
    log_warn "XFCE group not available. Installing individual XFCE packages."

    dnf install -y \
      xfce4-panel \
      xfce4-session \
      xfce4-settings \
      xfce4-terminal \
      thunar \
      garcon \
      tumbler \
      mousepad || true
  }

  log_info "Installing TigerVNC, X11 forwarding, fonts, and OpenGL packages..."

  dnf install -y \
    tigervnc-server \
    tigervnc \
    xorg-x11-xauth \
    xorg-x11-xinit \
    xorg-x11-server-Xorg \
    xorg-x11-apps \
    xorg-x11-utils \
    xorg-x11-fonts-100dpi \
    xorg-x11-fonts-75dpi \
    xorg-x11-fonts-Type1 \
    xorg-x11-fonts-misc \
    xterm \
    dbus-x11 \
    mesa-libGL \
    mesa-libGLU \
    mesa-dri-drivers \
    libglvnd \
    libglvnd-egl \
    libglvnd-glx \
    libglvnd-opengl \
    glx-utils \
    xclip \
    xsel \
    fontconfig \
    freetype \
    liberation-fonts \
    dejavu-sans-fonts \
    dejavu-serif-fonts \
    dejavu-sans-mono-fonts || true

  log_ok "VNC/XFCE/X11 packages installed or attempted."
}

# ------------------------------------------------------------------------------
# Input Helpers
# ------------------------------------------------------------------------------

vnc_read_tty() {
  local prompt="$1"
  local var_name="$2"

  if declare -F read_tty >/dev/null 2>&1; then
    read_tty "${prompt}" "${var_name}"
  else
    read -rp "${prompt}" "${var_name}" < /dev/tty
  fi
}

vnc_read_secret_tty() {
  local prompt="$1"
  local var_name="$2"

  if [[ -r /dev/tty ]]; then
    read -rsp "${prompt}" "${var_name}" < /dev/tty
    echo > /dev/tty
  else
    log_error "No interactive terminal available for password input."
    return 1
  fi
}

vnc_confirm() {
  local prompt="$1"
  local answer

  vnc_read_tty "${prompt}" answer

  case "${answer}" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Load / Collect Settings
# ------------------------------------------------------------------------------

vnc_load_or_collect_settings() {
  log_section "VNC Configuration Settings"

  VNC_CONFIG_DIR="/etc/capac-bootstrap"
  VNC_CONFIG_FILE="${VNC_CONFIG_DIR}/vnc.conf"

  mkdir -p "${VNC_CONFIG_DIR}"
  chmod 700 "${VNC_CONFIG_DIR}"

  if [[ -f "${VNC_CONFIG_FILE}" ]]; then
    log_info "Existing VNC configuration found: ${VNC_CONFIG_FILE}"

    # shellcheck source=/dev/null
    source "${VNC_CONFIG_FILE}"

    log_info "Saved VNC user      : ${VNC_USER:-not-set}"
    log_info "Saved VNC display   : :${VNC_DISPLAY:-1}"
    log_info "Saved VNC geometry  : ${VNC_GEOMETRY:-1920x1080}"
    log_info "Saved VNC depth     : ${VNC_DEPTH:-24}"
    log_info "Saved localhost mode: ${VNC_LOCALHOST:-yes}"

    if vnc_confirm "Reuse saved VNC settings? [Y/n]: "; then
      VNC_USER="${VNC_USER:-cadfem}"
      VNC_DISPLAY="${VNC_DISPLAY:-1}"
      VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
      VNC_DEPTH="${VNC_DEPTH:-24}"
      VNC_LOCALHOST="${VNC_LOCALHOST:-yes}"
      vnc_print_settings
      return 0
    fi
  fi

  VNC_USER="${VNC_USER:-}"
  VNC_DISPLAY="${VNC_DISPLAY:-1}"
  VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
  VNC_DEPTH="${VNC_DEPTH:-24}"
  VNC_LOCALHOST="${VNC_LOCALHOST:-yes}"

  if [[ -z "${VNC_USER}" ]]; then
    vnc_read_tty "Enter Linux username for VNC service [cadfem]: " VNC_USER
    VNC_USER="${VNC_USER:-cadfem}"
  fi

  local input_value

  vnc_read_tty "Enter VNC display number [${VNC_DISPLAY}]: " input_value
  VNC_DISPLAY="${input_value:-${VNC_DISPLAY}}"

  vnc_read_tty "Enter VNC geometry [${VNC_GEOMETRY}]: " input_value
  VNC_GEOMETRY="${input_value:-${VNC_GEOMETRY}}"

  vnc_read_tty "Enter VNC color depth [${VNC_DEPTH}]: " input_value
  VNC_DEPTH="${input_value:-${VNC_DEPTH}}"

  vnc_read_tty "Bind VNC to localhost only? yes/no [${VNC_LOCALHOST}]: " input_value
  VNC_LOCALHOST="${input_value:-${VNC_LOCALHOST}}"

  case "${VNC_LOCALHOST}" in
    y|Y|yes|YES|true|TRUE)
      VNC_LOCALHOST="yes"
      ;;
    n|N|no|NO|false|FALSE)
      VNC_LOCALHOST="no"
      ;;
    *)
      log_warn "Invalid localhost value. Defaulting to yes."
      VNC_LOCALHOST="yes"
      ;;
  esac

  vnc_print_settings
}

vnc_print_settings() {
  log_info "VNC user      : ${VNC_USER}"
  log_info "VNC display   : :${VNC_DISPLAY}"
  log_info "VNC port      : $((5900 + VNC_DISPLAY))"
  log_info "VNC geometry  : ${VNC_GEOMETRY}"
  log_info "VNC depth     : ${VNC_DEPTH}"
  log_info "Localhost only: ${VNC_LOCALHOST}"
}

# ------------------------------------------------------------------------------
# Validate / Create User
# ------------------------------------------------------------------------------

vnc_validate_user() {
  log_section "Validating VNC User"

  if id "${VNC_USER}" >/dev/null 2>&1; then
    log_ok "User exists: ${VNC_USER}"

    if vnc_confirm "Reset Linux password for ${VNC_USER}? [y/N]: "; then
      local linux_password_1
      local linux_password_2

      vnc_read_secret_tty "Enter new Linux password for ${VNC_USER}: " linux_password_1
      vnc_read_secret_tty "Confirm new Linux password for ${VNC_USER}: " linux_password_2

      if [[ "${linux_password_1}" != "${linux_password_2}" ]]; then
        log_error "Linux passwords do not match."
        return 1
      fi

      printf '%s:%s\n' "${VNC_USER}" "${linux_password_1}" | chpasswd
      log_ok "Linux password updated for user: ${VNC_USER}"

      unset linux_password_1 linux_password_2
    else
      log_info "Linux password unchanged for user: ${VNC_USER}"
    fi
  else
    log_warn "User does not exist: ${VNC_USER}"
    log_info "Creating user: ${VNC_USER}"

    useradd -m -s /bin/bash "${VNC_USER}"

    local linux_password_1
    local linux_password_2

    vnc_read_secret_tty "Enter Linux password for ${VNC_USER}: " linux_password_1
    vnc_read_secret_tty "Confirm Linux password for ${VNC_USER}: " linux_password_2

    if [[ "${linux_password_1}" != "${linux_password_2}" ]]; then
      log_error "Linux passwords do not match."
      return 1
    fi

    printf '%s:%s\n' "${VNC_USER}" "${linux_password_1}" | chpasswd

    unset linux_password_1 linux_password_2

    log_ok "User created and password set: ${VNC_USER}"
  fi

  VNC_HOME="$(getent passwd "${VNC_USER}" | cut -d: -f6)"
  VNC_GROUP="$(id -gn "${VNC_USER}")"

  if [[ -z "${VNC_HOME}" || ! -d "${VNC_HOME}" ]]; then
    log_error "Home directory not found for user ${VNC_USER}"
    return 1
  fi

  log_info "VNC home directory: ${VNC_HOME}"
  log_info "VNC primary group  : ${VNC_GROUP}"
}

# ------------------------------------------------------------------------------
# Prepare User VNC Config
# ------------------------------------------------------------------------------

vnc_prepare_user_config() {
  log_section "Preparing VNC User Configuration"

  install -d -m 700 -o "${VNC_USER}" -g "${VNC_GROUP}" "${VNC_HOME}/.vnc"

  if [[ -f "${VNC_HOME}/.vnc/passwd" ]]; then
    log_ok "VNC password file already exists."

    if vnc_confirm "Reset VNC password for ${VNC_USER}? [y/N]: "; then
      vnc_set_password
    else
      log_info "VNC password unchanged."
    fi
  else
    log_warn "VNC password is not set for user ${VNC_USER}."
    vnc_set_password
  fi

  chown -R "${VNC_USER}:${VNC_GROUP}" "${VNC_HOME}/.vnc"
  chmod 700 "${VNC_HOME}/.vnc"
  chmod 600 "${VNC_HOME}/.vnc/passwd" 2>/dev/null || true

  log_ok "VNC user configuration directory is ready."
}

vnc_set_password() {
  local vnc_password_1
  local vnc_password_2
  local use_same_answer

  if vnc_confirm "Use same password as Linux login? [y/N]: "; then
    log_warn "For security, the script will ask you to type it again."
  fi

  vnc_read_secret_tty "Enter VNC password for ${VNC_USER}: " vnc_password_1
  vnc_read_secret_tty "Confirm VNC password for ${VNC_USER}: " vnc_password_2

  if [[ "${vnc_password_1}" != "${vnc_password_2}" ]]; then
    log_error "VNC passwords do not match."
    return 1
  fi

  printf '%s\n' "${vnc_password_1}" | vncpasswd -f > "${VNC_HOME}/.vnc/passwd"

  chown "${VNC_USER}:${VNC_GROUP}" "${VNC_HOME}/.vnc/passwd"
  chmod 600 "${VNC_HOME}/.vnc/passwd"

  unset vnc_password_1 vnc_password_2 use_same_answer

  log_ok "VNC password configured for user: ${VNC_USER}"
}

# ------------------------------------------------------------------------------
# xstartup
# ------------------------------------------------------------------------------

vnc_create_xstartup() {
  log_section "Creating VNC xstartup"

  local xstartup="${VNC_HOME}/.vnc/xstartup"

  if [[ -f "${xstartup}" ]]; then
    cp -a "${xstartup}" "${xstartup}.bak.$(date +%Y%m%d%H%M%S)"
    log_ok "Existing xstartup backed up."
  fi

  cat > "${xstartup}" <<'EOF'
#!/usr/bin/env bash

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE

if command -v dbus-launch >/dev/null 2>&1; then
  exec dbus-launch --exit-with-session startxfce4
else
  exec startxfce4
fi
EOF

  chown "${VNC_USER}:${VNC_GROUP}" "${xstartup}"
  chmod 755 "${xstartup}"

  log_ok "Created VNC xstartup: ${xstartup}"
}

# ------------------------------------------------------------------------------
# systemd Service
# ------------------------------------------------------------------------------

vnc_create_systemd_service() {
  log_section "Creating systemd VNC Service"

  local service_file="/etc/systemd/system/vncserver@.service"

  if [[ -f "${service_file}" ]]; then
    cp -a "${service_file}" "${service_file}.bak.$(date +%Y%m%d%H%M%S)"
    log_ok "Existing VNC service file backed up."
  fi

  cat > "${service_file}" <<EOF
[Unit]
Description=TigerVNC Server for display :%i
After=network.target

[Service]
Type=forking
User=${VNC_USER}
Group=${VNC_GROUP}
WorkingDirectory=${VNC_HOME}

PIDFile=${VNC_HOME}/.vnc/%H:%i.pid

ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill :%i > /dev/null 2>&1 || true'
ExecStart=/usr/bin/vncserver :%i -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -localhost ${VNC_LOCALHOST}
ExecStop=/usr/bin/vncserver -kill :%i

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload

  log_ok "Created systemd service template: ${service_file}"
}

# ------------------------------------------------------------------------------
# Enable Service
# ------------------------------------------------------------------------------

vnc_enable_service() {
  log_section "Enabling VNC Service"

  local service_name="vncserver@${VNC_DISPLAY}.service"

  systemctl enable "${service_name}"

  if vnc_confirm "Start VNC service now on display :${VNC_DISPLAY}? [y/N]: "; then
    systemctl restart "${service_name}"
    log_ok "VNC service started: ${service_name}"
  else
    log_warn "VNC service enabled but not started."
    log_info "Start later with: sudo systemctl start ${service_name}"
  fi
}

# ------------------------------------------------------------------------------
# Save Safe Settings
# ------------------------------------------------------------------------------

vnc_save_settings() {
  log_section "Saving VNC Settings"

  cat > "${VNC_CONFIG_FILE}" <<EOF
# CAPAC VNC settings
# Safe configuration only. Plaintext passwords are not stored here.

VNC_USER="${VNC_USER}"
VNC_DISPLAY="${VNC_DISPLAY}"
VNC_GEOMETRY="${VNC_GEOMETRY}"
VNC_DEPTH="${VNC_DEPTH}"
VNC_LOCALHOST="${VNC_LOCALHOST}"
EOF

  chmod 600 "${VNC_CONFIG_FILE}"

  log_ok "Saved VNC settings: ${VNC_CONFIG_FILE}"
  log_warn "Passwords are not saved in plaintext."
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

vnc_summary() {
  log_section "VNC / GUI / X11 Summary"

  local service_name="vncserver@${VNC_DISPLAY}.service"
  local vnc_port=$((5900 + VNC_DISPLAY))

  log_info "VNC user      : ${VNC_USER}"
  log_info "VNC display   : :${VNC_DISPLAY}"
  log_info "VNC port      : ${vnc_port}"
  log_info "VNC geometry  : ${VNC_GEOMETRY}"
  log_info "VNC service   : ${service_name}"
  log_info "VNC xstartup  : ${VNC_HOME}/.vnc/xstartup"
  log_info "Saved config  : ${VNC_CONFIG_FILE}"

  log_info "Check service:"
  log_info "  sudo systemctl status ${service_name} --no-pager"

  log_info "Start service:"
  log_info "  sudo systemctl start ${service_name}"

  log_info "Stop service:"
  log_info "  sudo systemctl stop ${service_name}"

  if [[ "${VNC_LOCALHOST}" == "yes" ]]; then
    log_info "Secure SSH tunnel connection:"
    log_info "  ssh -L ${vnc_port}:localhost:${vnc_port} ${VNC_USER}@<server-ip>"
    log_info "  Then connect VNC client to localhost:${vnc_port}"
  else
    log_info "Direct VNC client connection:"
    log_info "  <server-ip>:${VNC_DISPLAY}"
    log_info "  or port ${vnc_port}"
  fi

  log_info "X11 forwarding test:"
  log_info "  ssh -X ${VNC_USER}@<server-ip>"
  log_info "  xclock"

  if command -v startxfce4 >/dev/null 2>&1; then
    log_ok "XFCE available: startxfce4"
  else
    log_warn "startxfce4 not found. XFCE may not be installed correctly."
  fi

  if command -v vncserver >/dev/null 2>&1; then
    log_ok "TigerVNC available: vncserver"
  else
    log_warn "vncserver command not found."
  fi

  if command -v xauth >/dev/null 2>&1; then
    log_ok "X11 forwarding helper available: xauth"
  else
    log_warn "xauth command not found."
  fi

  systemctl status "${service_name}" --no-pager || true
}