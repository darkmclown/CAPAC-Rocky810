#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/packages.sh
#
# Purpose:
#   Install common essential packages required for:
#   - Rocky 8.10 baseline administration
#   - CAE/HPC workloads
#   - ANSYS and engineering solver prerequisites
#   - FTP/SFTP/Samba/NFS file access
#   - Developer/compiler/runtime tools
#
# Required function for bootstrap:
#   packages_main()
# ==============================================================================

packages_main() {
  log_section "Installing Common Essential Packages for CAE/HPC/ANSYS"

  packages_prepare_repos
  packages_update_system
  packages_install_base_tools
  packages_install_network_tools
  packages_install_file_services
  packages_install_hpc_tools
  packages_install_dev_tools
  packages_install_ansys_prereqs
  packages_enable_services
  packages_summary

  log_ok "Common essential package installation completed."
}

# ------------------------------------------------------------------------------
# Repository Preparation
# ------------------------------------------------------------------------------

packages_prepare_repos() {
  log_section "Preparing Repositories"

  log_info "Installing Rocky repository utilities and EPEL..."

  dnf install -y \
    dnf-plugins-core \
    yum-utils \
    ca-certificates \
    curl \
    wget

  dnf install -y epel-release || {
    log_warn "EPEL installation failed from default repositories."
    log_warn "Trying direct EPEL package install..."

    dnf install -y \
      https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  }

  dnf config-manager --set-enabled powertools 2>/dev/null || true
  dnf config-manager --set-enabled PowerTools 2>/dev/null || true

  dnf makecache -y

  log_ok "Repository preparation completed."
}

# ------------------------------------------------------------------------------
# System Update
# ------------------------------------------------------------------------------

packages_update_system() {
  log_section "Updating System Packages"

  log_info "Running dnf update..."
  dnf update -y

  log_ok "System update completed."
}

# ------------------------------------------------------------------------------
# Base Administration Tools
# ------------------------------------------------------------------------------

packages_install_base_tools() {
  log_section "Installing Base Administration Tools"

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
    htop \
    iotop \
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
    tcpdump \
    time \
    tmux \
    traceroute \
    tree \
    unzip \
    vim-enhanced \
    wget \
    which \
    zip

  log_ok "Base administration tools installed."
}

# ------------------------------------------------------------------------------
# Network and Diagnostics Tools
# ------------------------------------------------------------------------------

packages_install_network_tools() {
  log_section "Installing Network and Diagnostic Tools"

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
    traceroute

  log_ok "Network and diagnostic tools installed."
}

# ------------------------------------------------------------------------------
# File Sharing Services: FTP, Samba, NFS
# ------------------------------------------------------------------------------

packages_install_file_services() {
  log_section "Installing File Transfer and File Sharing Services"

  dnf install -y \
    vsftpd \
    ftp \
    lftp \
    samba \
    samba-client \
    samba-common \
    samba-common-tools \
    cifs-utils \
    nfs-utils \
    autofs

  log_ok "FTP, Samba, CIFS, NFS, and AutoFS packages installed."
}

# ------------------------------------------------------------------------------
# CAE/HPC Runtime Tools
# ------------------------------------------------------------------------------

packages_install_hpc_tools() {
  log_section "Installing CAE/HPC Runtime Tools"

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
    opensm \
    pciutils \
    redhat-lsb-core \
    sysstat \
    tuned \
    zlib \
    zlib-devel || true

  log_ok "CAE/HPC runtime tools installed or attempted."
}

# ------------------------------------------------------------------------------
# Developer and Compiler Toolchain
# ------------------------------------------------------------------------------

packages_install_dev_tools() {
  log_section "Installing Developer and Compiler Toolchain"

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
    xz-devel

  log_ok "Developer and compiler toolchain installed."
}

# ------------------------------------------------------------------------------
# ANSYS / CAE Common Prerequisites
# ------------------------------------------------------------------------------

packages_install_ansys_prereqs() {
  log_section "Installing Common ANSYS / CAE Prerequisites"

  dnf install -y \
    alsa-lib \
    atk \
    cairo \
    cups-libs \
    dbus-libs \
    fontconfig \
    freetype \
    gcc \
    gcc-c++ \
    glib2 \
    glibc \
    gtk2 \
    gtk3 \
    libICE \
    libSM \
    libX11 \
    libX11-devel \
    libXau \
    libXcomposite \
    libXcursor \
    libXdamage \
    libXdmcp \
    libXext \
    libXfixes \
    libXft \
    libXi \
    libXinerama \
    libXmu \
    libXp \
    libXpm \
    libXrandr \
    libXrender \
    libXt \
    libXtst \
    libXxf86vm \
    libdrm \
    libglvnd \
    libglvnd-egl \
    libglvnd-glx \
    libglvnd-opengl \
    libjpeg-turbo \
    libpng \
    libstdc++ \
    libtiff \
    mesa-dri-drivers \
    mesa-libEGL \
    mesa-libGL \
    mesa-libGLU \
    mesa-libGLw \
    motif \
    ncurses \
    ncurses-compat-libs \
    nss \
    openmotif \
    pango \
    redhat-lsb-core \
    tcsh \
    xcb-util \
    xcb-util-image \
    xcb-util-keysyms \
    xcb-util-renderutil \
    xcb-util-wm \
    xorg-x11-apps \
    xorg-x11-fonts-100dpi \
    xorg-x11-fonts-75dpi \
    xorg-x11-fonts-Type1 \
    xorg-x11-fonts-misc \
    xorg-x11-server-Xorg \
    xorg-x11-xauth \
    xorg-x11-xinit \
    xorg-x11-xkb-utils \
    xterm || true

  log_ok "Common ANSYS / CAE prerequisite packages installed or attempted."
}

# ------------------------------------------------------------------------------
# Enable Required Services
# ------------------------------------------------------------------------------

packages_enable_services() {
  log_section "Enabling Base Services"

  systemctl enable --now sshd || true
  systemctl enable --now chronyd || true
  systemctl enable --now crond || true
  systemctl enable --now tuned || true

  # File sharing services are installed but not fully configured here.
  # Configuration will be handled in future dedicated modules.
  systemctl enable vsftpd || true
  systemctl enable smb || true
  systemctl enable nmb || true
  systemctl enable nfs-server || true
  systemctl enable autofs || true

  log_ok "Base services enabled."
  log_warn "FTP, Samba, and NFS are installed but not fully configured yet."
  log_warn "Dedicated configuration modules should handle users, shares, firewall, and SELinux."
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

packages_summary() {
  log_section "Package Installation Summary"

  log_info "Checking key tools..."

  local commands=(
    git
    curl
    wget
    rsync
    ftp
    lftp
    smbclient
    showmount
    module
    gcc
    g++
    gfortran
    python3
    pip3
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

  log_info "Installed repository list:"
  dnf repolist | tee -a "${LOG_FILE}" || true

  log_info "Enabled important services:"
  systemctl is-enabled sshd chronyd crond tuned vsftpd smb nmb nfs-server autofs 2>/dev/null | tee -a "${LOG_FILE}" || true
}