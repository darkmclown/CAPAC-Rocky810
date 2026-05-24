#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/030-ntp.sh
#
# Purpose:
#   Configure time, Chrony/NTP, IPv4 priority, and safe network performance tuning.
#
# Provides:
#   - Asia/Kolkata timezone
#   - Chrony using Cloudflare time service
#   - NTS-secured Cloudflare time where supported
#   - Fallback plain Cloudflare NTP
#   - Hardware clock synchronization
#   - IPv4 preference
#   - Safe HPC/CAE network sysctl tuning
#
# Required function:
#   ntp_main()
# ==============================================================================

ntp_main() {
  log_section "NTP / Chrony / IPv4 / Network Performance Module"

  ntp_install_packages
  ntp_set_timezone_ist
  ntp_configure_chrony_cloudflare
  ntp_configure_ipv4_priority
  ntp_apply_network_performance_tuning
  ntp_restart_services
  ntp_summary

  log_ok "NTP / Chrony / IPv4 / Network Performance module completed successfully."
}

# ------------------------------------------------------------------------------
# Install Required Packages
# ------------------------------------------------------------------------------

ntp_install_packages() {
  log_section "Installing Time and Network Packages"

  dnf install -y \
    chrony \
    tzdata \
    ca-certificates \
    iproute \
    iputils \
    ethtool \
    bind-utils \
    tcpdump \
    traceroute \
    mtr \
    iperf3

  log_ok "Required time/network packages installed."
}

# ------------------------------------------------------------------------------
# Timezone / RTC
# ------------------------------------------------------------------------------

ntp_set_timezone_ist() {
  log_section "Setting System Timezone to IST"

  timedatectl set-timezone Asia/Kolkata

  # Best practice for Linux servers is RTC in UTC.
  # But the user requested local/system time alignment to IST.
  # This sets the hardware clock mode to local time.
  timedatectl set-local-rtc 1 --adjust-system-clock || true

  log_ok "Timezone set to Asia/Kolkata."
  log_warn "RTC is configured as local time because requested."
  log_warn "Note: Universal time itself remains UTC by definition; local system time is IST."
}

# ------------------------------------------------------------------------------
# Chrony Cloudflare Configuration
# ------------------------------------------------------------------------------

ntp_configure_chrony_cloudflare() {
  log_section "Configuring Chrony with Cloudflare Time"

  if [[ -f /etc/chrony.conf ]]; then
    cp -a /etc/chrony.conf "/etc/chrony.conf.bak.$(date +%Y%m%d%H%M%S)"
    log_ok "Existing /etc/chrony.conf backed up."
  fi

  cat > /etc/chrony.conf <<'EOF'
# ==============================================================================
# CAPAC Chrony Configuration
# Cloudflare NTP/NTS preferred
# ==============================================================================

# Cloudflare secure time service.
# Uses NTS when supported by chrony/network path.
server time.cloudflare.com iburst nts

# Fallback plain NTP to Cloudflare in case NTS handshake is blocked.
server time.cloudflare.com iburst

# Allow fast correction during boot.
makestep 1.0 3

# Sync RTC from system clock.
rtcsync

# Drift file.
driftfile /var/lib/chrony/drift

# Reduce noisy client logging.
noclientlog

# Allow chronyc local command access only.
bindcmdaddress 127.0.0.1
bindcmdaddress ::1

# Do not serve time to network clients in this module.
# If this node should become a cluster NTP server, create a separate ntp-server module.
# allow 192.168.0.0/16

# Logging.
logdir /var/log/chrony
EOF

  log_ok "Chrony configured to use Cloudflare time service."

  log_info "Cloudflare provides time.cloudflare.com for NTP, and supports NTS for authenticated time synchronization."
}

# ------------------------------------------------------------------------------
# IPv4 Priority
# ------------------------------------------------------------------------------

ntp_configure_ipv4_priority() {
  log_section "Prioritizing IPv4"

  if [[ -f /etc/gai.conf ]]; then
    cp -a /etc/gai.conf "/etc/gai.conf.bak.$(date +%Y%m%d%H%M%S)"
  fi

  touch /etc/gai.conf

  if grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf; then
    log_ok "IPv4 precedence already configured in /etc/gai.conf."
  else
    cat >> /etc/gai.conf <<'EOF'

# CAPAC: Prefer IPv4-mapped addresses over IPv6.
precedence ::ffff:0:0/96  100
EOF
    log_ok "IPv4 address precedence added to /etc/gai.conf."
  fi

  # Keep IPv6 enabled by default, but avoid IPv6 being preferred.
  # Full IPv6 disablement should be handled separately only if required.
  log_warn "IPv6 is not disabled. Only IPv4 preference is configured."
}

# ------------------------------------------------------------------------------
# Network Performance Tuning
# ------------------------------------------------------------------------------

ntp_apply_network_performance_tuning() {
  log_section "Applying Safe Network Performance Tuning"

  cat > /etc/sysctl.d/90-capac-network-performance.conf <<'EOF'
# ==============================================================================
# CAPAC CAE/HPC Network Performance Tuning
# Safe baseline for Rocky 8.10 servers
# ==============================================================================

# Larger TCP buffers for high-throughput CAE/HPC file movement.
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 262144
net.core.wmem_default = 262144

net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Better connection backlog handling.
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# Enable TCP window scaling and timestamps.
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1

# Enable SACK for better recovery on lossy paths.
net.ipv4.tcp_sack = 1

# Reuse TIME_WAIT sockets safely for outgoing connections.
net.ipv4.tcp_tw_reuse = 1

# Keep syncookies enabled.
net.ipv4.tcp_syncookies = 1

# Avoid source-routed packets.
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Ignore bogus ICMP errors.
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Reverse path filtering.
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Keep forwarding disabled by default.
# Enable only in a dedicated router/NAT module if required.
net.ipv4.ip_forward = 0
EOF

  sysctl --system

  log_ok "Network performance sysctl tuning applied."
}

# ------------------------------------------------------------------------------
# Restart Services
# ------------------------------------------------------------------------------

ntp_restart_services() {
  log_section "Restarting Time Services"

  systemctl enable --now chronyd
  systemctl restart chronyd

  sleep 3

  chronyc -a makestep || true

  log_ok "Chrony enabled and restarted."
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

ntp_summary() {
  log_section "NTP / Time / Network Summary"

  log_info "Timedatectl:"
  timedatectl | tee -a "${LOG_FILE}" || true

  log_info "Chrony tracking:"
  chronyc tracking | tee -a "${LOG_FILE}" || true

  log_info "Chrony sources:"
  chronyc sources -v | tee -a "${LOG_FILE}" || true

  log_info "Cloudflare DNS resolution:"
  getent ahosts time.cloudflare.com | tee -a "${LOG_FILE}" || true

  log_info "IPv4 preference check:"
  grep -n "precedence ::ffff:0:0/96" /etc/gai.conf | tee -a "${LOG_FILE}" || true

  log_info "Network tuning file:"
  cat /etc/sysctl.d/90-capac-network-performance.conf | tee -a "${LOG_FILE}" || true

  log_info "Key sysctl values:"
  sysctl \
    net.core.rmem_max \
    net.core.wmem_max \
    net.ipv4.tcp_rmem \
    net.ipv4.tcp_wmem \
    net.core.somaxconn \
    net.ipv4.tcp_max_syn_backlog \
    net.ipv4.ip_forward | tee -a "${LOG_FILE}" || true

  log_ok "NTP/time/network summary completed."
}