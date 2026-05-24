#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/040-security.sh
#
# Purpose:
#   HPC/CAE open-performance security baseline.
#
# Applies:
#   - Disable SELinux
#   - Disable firewalld
#   - Disable nftables/iptables services if present
#   - Unlock soft/hard ulimits
#   - Unlock core dumps
#   - Increase process/file/memory limits
#   - Tune kernel semaphores/shared memory
#   - Relax PAM limits
#   - Unlock /etc/securetty
#   - Relax SSH restrictions for HPC/admin access
#
# WARNING:
#   This is an open internal-network HPC profile.
#   Use only in trusted private network environments.
#
# Required function:
#   security_main()
# ==============================================================================

security_main() {
  log_section "Security / Limits / HPC Open Performance Module"

  security_backup_core_files
  security_disable_selinux
  security_disable_firewall
  security_unlock_securetty
  security_configure_limits
  security_configure_pam_limits
  security_configure_sysctl_hpc
  security_configure_systemd_limits
  security_configure_ssh
  security_apply_changes
  security_summary

  log_ok "Security / Limits / HPC open-performance module completed successfully."
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

security_backup_file() {
  local file="$1"

  if [[ -f "${file}" ]]; then
    cp -a "${file}" "${file}.bak.$(date +%Y%m%d%H%M%S)"
    log_ok "Backup created: ${file}"
  else
    log_warn "File not found, backup skipped: ${file}"
  fi
}

security_set_or_append() {
  local key="$1"
  local value="$2"
  local file="$3"

  touch "${file}"

  if grep -qE "^[#[:space:]]*${key}[[:space:]]+" "${file}"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|g" "${file}"
  else
    echo "${key} ${value}" >> "${file}"
  fi
}

security_backup_core_files() {
  log_section "Backing Up Security Configuration Files"

  security_backup_file /etc/selinux/config
  security_backup_file /etc/security/limits.conf
  security_backup_file /etc/pam.d/su
  security_backup_file /etc/pam.d/sshd
  security_backup_file /etc/ssh/sshd_config
  security_backup_file /etc/securetty
  security_backup_file /etc/systemd/system.conf
  security_backup_file /etc/systemd/user.conf

  log_ok "Backup phase completed."
}

# ------------------------------------------------------------------------------
# SELinux
# ------------------------------------------------------------------------------

security_disable_selinux() {
  log_section "Disabling SELinux"

  if command -v getenforce >/dev/null 2>&1; then
    log_info "Current SELinux mode: $(getenforce || true)"
  fi

  if [[ -f /etc/selinux/config ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
    log_ok "SELINUX=disabled set in /etc/selinux/config"
  fi

  if command -v setenforce >/dev/null 2>&1; then
    setenforce 0 2>/dev/null || true
  fi

  log_warn "SELinux full disable requires reboot."
}

# ------------------------------------------------------------------------------
# Firewall
# ------------------------------------------------------------------------------

security_disable_firewall() {
  log_section "Disabling Firewall Services"

  local services=(
    firewalld
    nftables
    iptables
    ip6tables
  )

  local svc

  for svc in "${services[@]}"; do
    if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
      log_info "Disabling service: ${svc}"
      systemctl disable --now "${svc}" || true
      systemctl mask "${svc}" || true
      log_ok "Disabled/masked: ${svc}"
    else
      log_info "Service not present: ${svc}"
    fi
  done

  log_warn "Firewall disabled. Use only on trusted private HPC networks."
}

# ------------------------------------------------------------------------------
# securetty
# ------------------------------------------------------------------------------

security_unlock_securetty() {
  log_section "Unlocking securetty"

  if [[ -f /etc/securetty ]]; then
    cp -a /etc/securetty "/etc/securetty.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > /etc/securetty <<'EOF'
console
tty1
tty2
tty3
tty4
tty5
tty6
pts/0
pts/1
pts/2
pts/3
pts/4
pts/5
pts/6
pts/7
pts/8
pts/9
pts/10
EOF

  chmod 600 /etc/securetty

  log_ok "/etc/securetty unlocked for console, tty, and pts sessions."
}

# ------------------------------------------------------------------------------
# Limits
# ------------------------------------------------------------------------------

security_configure_limits() {
  log_section "Configuring HPC ulimits"

  cat > /etc/security/limits.d/99-capac-hpc-limits.conf <<'EOF'
# ==============================================================================
# CAPAC HPC Solver Limits
# ==============================================================================

# Unlock file descriptors.
* soft nofile 1048576
* hard nofile 1048576

# Unlock processes/threads.
* soft nproc 1048576
* hard nproc 1048576

# Unlock locked memory for MPI/RDMA/solver usage.
* soft memlock unlimited
* hard memlock unlimited

# Unlock stack.
* soft stack unlimited
* hard stack unlimited

# Unlock core dumps.
* soft core unlimited
* hard core unlimited

# Unlock address space / data / file size.
* soft as unlimited
* hard as unlimited
* soft data unlimited
* hard data unlimited
* soft fsize unlimited
* hard fsize unlimited
* soft rss unlimited
* hard rss unlimited

# Root limits.
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 1048576
root hard nproc 1048576
root soft memlock unlimited
root hard memlock unlimited
root soft stack unlimited
root hard stack unlimited
root soft core unlimited
root hard core unlimited
root soft as unlimited
root hard as unlimited
EOF

  log_ok "HPC limits written to /etc/security/limits.d/99-capac-hpc-limits.conf"
}

# ------------------------------------------------------------------------------
# PAM Limits
# ------------------------------------------------------------------------------

security_configure_pam_limits() {
  log_section "Ensuring PAM Limits Are Enabled"

  local pam_files=(
    /etc/pam.d/login
    /etc/pam.d/sshd
    /etc/pam.d/su
    /etc/pam.d/system-auth
    /etc/pam.d/password-auth
  )

  local pam_file

  for pam_file in "${pam_files[@]}"; do
    if [[ -f "${pam_file}" ]]; then
      if grep -q "pam_limits.so" "${pam_file}"; then
        log_ok "pam_limits already present in ${pam_file}"
      else
        echo "session required pam_limits.so" >> "${pam_file}"
        log_ok "Added pam_limits to ${pam_file}"
      fi
    fi
  done
}

# ------------------------------------------------------------------------------
# Kernel / Sysctl HPC Tuning
# ------------------------------------------------------------------------------

security_configure_sysctl_hpc() {
  log_section "Configuring HPC Kernel Limits and Semaphores"

  cat > /etc/sysctl.d/91-capac-hpc-security-limits.conf <<'EOF'
# ==============================================================================
# CAPAC HPC Kernel / Solver Runtime Limits
# ==============================================================================

# Core dumps.
kernel.core_pattern = /var/core/core.%e.%p.%h.%t
fs.suid_dumpable = 2

# Maximum file handles.
fs.file-max = 20971520

# Max mmap areas for large solver workloads.
vm.max_map_count = 1048576

# Shared memory.
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
kernel.shmmni = 4096

# Semaphores:
# SEMMSL SEMMNS SEMOPM SEMMNI
kernel.sem = 1024 1048576 1024 4096

# Message queues.
kernel.msgmni = 65536
kernel.msgmax = 65536
kernel.msgmnb = 65536

# PID/thread scalability.
kernel.pid_max = 4194304
kernel.threads-max = 4194304

# Swappiness for solver servers.
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5

# Network backlog useful for cluster workloads.
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_max_syn_backlog = 16384

# Keep forwarding disabled unless this node is a router.
net.ipv4.ip_forward = 0
EOF

  mkdir -p /var/core
  chmod 1777 /var/core

  sysctl --system

  log_ok "HPC sysctl limits applied."
}

# ------------------------------------------------------------------------------
# systemd Limits
# ------------------------------------------------------------------------------

security_configure_systemd_limits() {
  log_section "Configuring systemd Default Limits"

  mkdir -p /etc/systemd/system.conf.d
  mkdir -p /etc/systemd/user.conf.d

  cat > /etc/systemd/system.conf.d/99-capac-hpc-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitSTACK=infinity
DefaultLimitCORE=infinity
DefaultTasksMax=infinity
EOF

  cat > /etc/systemd/user.conf.d/99-capac-hpc-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitSTACK=infinity
DefaultLimitCORE=infinity
DefaultTasksMax=infinity
EOF

  systemctl daemon-reexec || true
  systemctl daemon-reload || true

  log_ok "systemd limits configured."
}

# ------------------------------------------------------------------------------
# SSH Unlock
# ------------------------------------------------------------------------------

security_configure_ssh() {
  log_section "Configuring SSH for HPC Access"

  local sshd_config="/etc/ssh/sshd_config"

  if [[ ! -f "${sshd_config}" ]]; then
    log_error "Missing ${sshd_config}"
    return 1
  fi

  security_set_or_append "PermitRootLogin" "yes" "${sshd_config}"
  security_set_or_append "PasswordAuthentication" "yes" "${sshd_config}"
  security_set_or_append "PubkeyAuthentication" "yes" "${sshd_config}"
  security_set_or_append "X11Forwarding" "yes" "${sshd_config}"
  security_set_or_append "X11UseLocalhost" "no" "${sshd_config}"
  security_set_or_append "TCPKeepAlive" "yes" "${sshd_config}"
  security_set_or_append "ClientAliveInterval" "300" "${sshd_config}"
  security_set_or_append "ClientAliveCountMax" "3" "${sshd_config}"
  security_set_or_append "UsePAM" "yes" "${sshd_config}"
  security_set_or_append "UseDNS" "no" "${sshd_config}"
  security_set_or_append "MaxSessions" "100" "${sshd_config}"
  security_set_or_append "MaxStartups" "100:30:200" "${sshd_config}"

  if sshd -t; then
    systemctl restart sshd
    log_ok "sshd_config validated and sshd restarted."
  else
    log_error "sshd_config validation failed."
    return 1
  fi
}

# ------------------------------------------------------------------------------
# Apply Runtime Changes
# ------------------------------------------------------------------------------

security_apply_changes() {
  log_section "Applying Runtime Security/Limit Changes"

  ulimit -n 1048576 || true
  ulimit -u 1048576 || true
  ulimit -c unlimited || true
  ulimit -s unlimited || true
  ulimit -l unlimited || true

  log_ok "Runtime shell ulimits applied where possible."
  log_warn "User sessions must logout/login again to inherit PAM limits."
  log_warn "A reboot is recommended after SELinux, systemd, and kernel limit changes."
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

security_summary() {
  log_section "Security / HPC Limits Summary"

  log_info "SELinux:"
  if command -v getenforce >/dev/null 2>&1; then
    getenforce | tee -a "${LOG_FILE}" || true
  fi
  grep '^SELINUX=' /etc/selinux/config | tee -a "${LOG_FILE}" || true

  log_info "Firewall services:"
  systemctl is-enabled firewalld nftables iptables ip6tables 2>/dev/null | tee -a "${LOG_FILE}" || true
  systemctl is-active firewalld nftables iptables ip6tables 2>/dev/null | tee -a "${LOG_FILE}" || true

  log_info "Limits:"
  ulimit -a | tee -a "${LOG_FILE}" || true

  log_info "Limits file:"
  cat /etc/security/limits.d/99-capac-hpc-limits.conf | tee -a "${LOG_FILE}" || true

  log_info "Sysctl HPC values:"
  sysctl \
    fs.file-max \
    vm.max_map_count \
    kernel.sem \
    kernel.shmmax \
    kernel.shmall \
    kernel.threads-max \
    kernel.pid_max \
    net.core.somaxconn \
    net.core.netdev_max_backlog | tee -a "${LOG_FILE}" || true

  log_info "SSH key settings:"
  grep -E '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|X11Forwarding|X11UseLocalhost|UsePAM|UseDNS|MaxSessions|MaxStartups)' /etc/ssh/sshd_config | tee -a "${LOG_FILE}" || true

  log_ok "Security / HPC limits summary completed."
}