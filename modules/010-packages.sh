#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/010-packages.sh
#
# Purpose:
#   Install common essential packages for Rocky CAE/HPC baseline.
#
# Includes:
#   - One-time system update
#   - EPEL release
#   - Admin tools
#   - Monitoring tools: htop, iotop, iftop, sysstat
#   - Network tools
#   - FTP/SFTP tools
#   - Samba/NFS clients and services
#   - Developer essentials
#   - Basic CAE/HPC prerequisites
#
# Required function:
#   packages_main()
# ==============================================================================

packages_main() {
  log_section "Common Packages Module"

  packages_check_os
  packages_prepare_repositories
  packages_update_once
  packages_install_admin_tools
  packages_install_monitoring_tools
  packages_install_network_tools
  packages_install_file_transfer_tools
  packages_install_fileshare_tools
  packages_install_dev_tools
  packages_install_cae_hpc_prereqs
  packages_enable_basic_services
  packages_summary

  log_ok "Common packages module completed successfully."
}

# ------------------------------------------------------------------------------
# OS Check
# ------------------------------------------------------------------------------

packages_check_os() {
  log_section "Checking Rocky Linux Package Environment"

  if [[ -f /etc/rocky-release ]]; then
    log_info "Detected: $(cat /etc/rocky-release)"
  else
    log_warn "Rocky release file not found. Continuing carefully."
  fi

  if ! command -v dnf >/dev/null 2>&1; then
    log_error "dnf command not found. Cannot continue package installation."
    return 1
  fi

  log_ok "dnf package manager available."
}

# ------------------------------------------------------------------------------
# Repository Setup
# ------------------------------------------------------------------------------

packages_prepare_repositories() {
  log_section "Preparing Repositories"

  log_info "Installing repository utilities..."

  dnf install -y \
    dnf-plugins-core \
    yum-utils \
    ca-certificates \
    curl \
    wget

  log_info "Installing EPEL release..."

  if rpm -q epel-release >/dev/null 2>&1; then
    log_ok "EPEL release already installed."
  else
    dnf install -y epel-release || {
      log_warn "EPEL install from enabled repositories failed. Trying official EPEL RPM."

      dnf install -y \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    }
  fi

  log_info "Enabling CodeReady/PowerTools repositories where available..."

  dnf config-manager --set-enabled powertools 2>/dev/null || true
  dnf config-manager --set-enabled PowerTools 2>/dev/null || true
  dnf config-manager --set-enabled crb 2>/dev/null || true

  log_info "Refreshing package metadata..."
  dnf makecache -y

  log_ok "Repository preparation completed."
}

# ------------------------------------------------------------------------------
# Update Once
# ------------------------------------------------------------------------------

packages_update_once() {
  log_section "System Update"

  local update_marker="/var/lib/capac-bootstrap/packages-update.done"

  mkdir -p /var/lib/capac-bootstrap

  if [[ -f "${update_marker}" ]]; then
    log_ok "System update already completed earlier. Skipping dnf update."
    log_info "Marker: ${update_marker}"
    return 0
  fi

  log_info "Running one-time system update..."
  dnf update -y

  date > "${update_marker}"

  log_ok "System update completed."
}

# ------------------------------------------------------------------------------
# Admin Essentials
# ------------------------------------------------------------------------------

packages_install_admin_tools() {
  log_section "Installing Admin Essentials"

  dnf install -y \
    bash-completion \
    bind-utils \
    bzip2 \
    chrony \
    cronie \
    curl \
    dos2unix \
    file \
    git \
    hostname \
    jq \
    less \
    lsof \
    man-db \
    man-pages \
    mlocate \
    nano \
    net-tools \
    nmap-ncat \
    openssh-clients \
    openssh-server \
    patch \
    pciutils \
    procps-ng \
    psmisc \
    rsync \
    screen \
    sos \
    tar \
    time \
    tmux \
    traceroute \
    tree \
    unzip \
    vim-enhanced \
    wget \
    which \
    zip

  log_ok "Admin essentials installed."
}

# ------------------------------------------------------------------------------
# Monitoring Essentials
# ------------------------------------------------------------------------------

packages_install_monitoring_tools() {
  log_section "Installing Monitoring and Performance Tools"

  dnf install -y \
    htop \
    iotop \
    iftop \
    nmon \
    sysstat \
    dstat \
    glances \
    lshw \
    smartmontools \
    lm_sensors \
    strace \
    perf \
    tuned || true

  log_ok "Monitoring and performance tools installed or attempted."
}

# ------------------------------------------------------------------------------
# Network Tools
# ------------------------------------------------------------------------------

packages_install_network_tools() {
  log_section "Installing Network Tools"

  dnf install -y \
    ethtool \
    iperf3 \
    iproute \
    iputils \
    lldpad \
    mtr \
    nc \
    nmap \
    tcpdump \
    telnet \
    traceroute \
    whois

  log_ok "Network tools installed."
}

# ------------------------------------------------------------------------------
# FTP / SFTP / Transfer Tools
# ------------------------------------------------------------------------------

packages_install_file_transfer_tools() {
  log_section "Installing FTP/SFTP/File Transfer Tools"

  dnf install -y \
    vsftpd \
    ftp \
    lftp \
    openssh-clients \
    openssh-server \
    rsync \
    wget \
    curl

  log_ok "FTP, SFTP, and file transfer tools installed."
}

# ------------------------------------------------------------------------------
# Samba / NFS / CIFS
# ------------------------------------------------------------------------------

packages_install_fileshare_tools() {
  log_section "Installing Samba, NFS, and CIFS Tools"

  dnf install -y \
    samba \
    samba-client \
    samba-common \
    samba-common-tools \
    cifs-utils \
    nfs-utils \
    autofs

  log_ok "Samba, NFS, CIFS, and AutoFS packages installed."
}

# ------------------------------------------------------------------------------
# Developer Essentials
# ------------------------------------------------------------------------------

packages_install_dev_tools() {
  log_section "Installing Developer Essentials"

  dnf groupinstall -y "Development Tools" || {
    log_warn "Development Tools group install failed. Continuing with individual packages."
  }

  dnf install -y \
    autoconf \
    automake \
    binutils \
    bison \
    cmake \
    elfutils-libelf-devel \
    flex \
    gcc \
    gcc-c++ \
    gcc-gfortran \
    gdb \
    glibc \
    glibc-common \
    glibc-devel \
    glibc-headers \
    kernel-devel \
    kernel-headers \
    libgcc \
    libgfortran \
    libgomp \
    libstdc++ \
    libstdc++-devel \
    make \
    openssl \
    openssl-devel \
    patch \
    perl \
    python3 \
    python3-devel \
    python3-pip \
    readline-devel \
    rpm-build \
    sqlite-devel \
    tk-devel \
    xz-devel \
    zlib \
    zlib-devel

  log_ok "Developer essentials installed."
}

# ------------------------------------------------------------------------------
# CAE / HPC Prerequisites
# ------------------------------------------------------------------------------

packages_install_cae_hpc_prereqs() {
  log_section "Installing CAE/HPC Common Prerequisites"

  dnf install -y \
    environment-modules \
    hwloc \
    hwloc-libs \
    libibverbs \
    libibverbs-utils \
    rdma-core \
    rdma-core-devel \
    numactl \
    numactl-devel \
    numactl-libs \
    openmpi \
    openmpi-devel \
    pciutils \
    redhat-lsb-core \
    tcsh \
    xorg-x11-xauth \
    xorg-x11-apps \
    xterm \
    mesa-libGL \
    mesa-libGLU \
    mesa-dri-drivers \
    libX11 \
    libXext \
    libXrender \
    libXt \
    libXtst \
    libXi \
    libXmu \
    libXpm \
    libXrandr \
    libXcursor \
    libXinerama \
    fontconfig \
    freetype \
    motif \
    gtk2 \
    gtk3 || true

  log_ok "CAE/HPC prerequisites installed or attempted."
}

# ------------------------------------------------------------------------------
# Enable Basic Services
# ------------------------------------------------------------------------------

packages_enable_basic_services() {
  log_section "Enabling Basic Services"

  systemctl enable --now sshd || true
  systemctl enable --now chronyd || true
  systemctl enable --now crond || true
  systemctl enable --now tuned || true
  systemctl enable --now sysstat || true

  # Installed but not started/configured here.
  # Dedicated modules should configure firewall, SELinux, users, shares and exports.
  systemctl enable vsftpd || true
  systemctl enable smb || true
  systemctl enable nmb || true
  systemctl enable nfs-server || true
  systemctl enable autofs || true

  log_ok "Base services enabled."
  log_warn "FTP, Samba, and NFS are installed/enabled but not configured in this module."
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

packages_summary() {
  log_section "Common Packages Summary"

  local commands=(
    git
    curl
    wget
    htop
    iotop
    iftop
    nmon
    sar
    iostat
    gcc
    g++
    gfortran
    python3
    pip3
    ftp
    lftp
    rsync
    smbclient
    showmount
    exportfs
    module
    chronyc
    tuned-adm
  )

  local cmd

  for cmd in "${commands[@]}"; do
    if command -v "${cmd}" >/dev/null 2>&1; then
      log_ok "Available: ${cmd}"
    else
      log_warn "Missing or not in PATH: ${cmd}"
    fi
  done

  log_info "Enabled repositories:"
  dnf repolist | tee -a "${LOG_FILE}" || true

  log_info "Important service enablement status:"
  systemctl is-enabled \
    sshd \
    chronyd \
    crond \
    tuned \
    sysstat \
    vsftpd \
    smb \
    nmb \
    nfs-server \
    autofs 2>/dev/null | tee -a "${LOG_FILE}" || true
}