#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/050-slurm.sh
#
# Purpose:
#   Slurm + Munge + MariaDB accounting + Environment Modules + MPI
#   for CAPAC 2-node CAE/HPC CFD cluster.
#
# Nodes:
#   cae-01 / 192.168.2.131 : master + compute
#   cae-03 / 192.168.2.133 : compute
#
# Access model:
#   hpc group controls job-user access.
#   cadfem and slurm are added to hpc.
#   Future users can be added using:
#     sudo capac-add-hpc-user <username>
#
# Required function:
#   slurm_main()
# ==============================================================================

slurm_main() {
  log_section "Slurm + Munge + MariaDB + Environment Modules + HPC Access"

  slurm_set_defaults
  slurm_detect_role
  slurm_validate_hostname
  slurm_configure_hosts
  slurm_install_packages
  slurm_create_users_groups_dirs
  slurm_install_hpc_user_helper
  slurm_configure_munge
  slurm_configure_mariadb_if_master
  slurm_write_configs
  slurm_configure_environment_modules
  slurm_configure_intel_mpi_module
  slurm_setup_root_ssh_if_master
  slurm_sync_to_compute_if_master
  slurm_enable_services
  slurm_enable_boot_persistence
  slurm_register_accounting_if_master
  slurm_create_test_jobs_if_master
  slurm_summary

  log_ok "Slurm module completed successfully."
}

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------

slurm_set_defaults() {
  CLUSTER_NAME="${CLUSTER_NAME:-capac-hpc}"
  PARTITION_NAME="${PARTITION_NAME:-cfd}"

  MASTER_HOST="${MASTER_HOST:-cae-01}"
  MASTER_IP="${MASTER_IP:-192.168.2.131}"

  COMPUTE_HOST="${COMPUTE_HOST:-cae-03}"
  COMPUTE_IP="${COMPUTE_IP:-192.168.2.133}"

  NODE_CPUS="${NODE_CPUS:-40}"
  NODE_REALMEMORY="${NODE_REALMEMORY:-380000}"

  SHARED_APP_PATH="${SHARED_APP_PATH:-/opt/apps}"
  MODULEFILES_PATH="${MODULEFILES_PATH:-/opt/modulefiles}"
  SHARED_DATA_PATH="${SHARED_DATA_PATH:-/home/data}"
  SHARED_SCRATCH_PATH="${SHARED_SCRATCH_PATH:-/home/data/scratch}"

  SLURM_USER="${SLURM_USER:-slurm}"
  RUN_USER="${RUN_USER:-cadfem}"
  HPC_GROUP="${HPC_GROUP:-hpc}"
  SSH_ADMIN_USER="${SSH_ADMIN_USER:-cadfem}"

  SLURM_DB_NAME="${SLURM_DB_NAME:-slurm_acct_db}"
  SLURM_DB_USER="${SLURM_DB_USER:-slurm}"
  SLURM_DB_PASS_FILE="${SLURM_DB_PASS_FILE:-/etc/slurm/slurmdbd.password}"

  INTEL_ONEAPI_ROOT="${INTEL_ONEAPI_ROOT:-/opt/intel/oneapi}"
  INSTALL_INTEL_MPI="${INSTALL_INTEL_MPI:-ask}"

  log_section "Slurm Defaults"
  log_info "Cluster          : ${CLUSTER_NAME}"
  log_info "Partition        : ${PARTITION_NAME}"
  log_info "Master           : ${MASTER_HOST} / ${MASTER_IP}"
  log_info "Compute          : ${COMPUTE_HOST} / ${COMPUTE_IP}"
  log_info "CPUs per node    : ${NODE_CPUS}"
  log_info "Memory per node  : ${NODE_REALMEMORY} MB"
  log_info "Run user         : ${RUN_USER}"
  log_info "Slurm user       : ${SLURM_USER}"
  log_info "HPC group        : ${HPC_GROUP}"
  log_info "Apps path        : ${SHARED_APP_PATH}"
  log_info "Modulefiles path : ${MODULEFILES_PATH}"
  log_info "Data path        : ${SHARED_DATA_PATH}"
  log_info "Scratch path     : ${SHARED_SCRATCH_PATH}"
}

# ------------------------------------------------------------------------------
# Input helpers
# ------------------------------------------------------------------------------

slurm_read_tty() {
  local prompt="$1"
  local var_name="$2"

  if declare -F read_tty >/dev/null 2>&1; then
    read_tty "${prompt}" "${var_name}"
  else
    read -rp "${prompt}" "${var_name}" < /dev/tty
  fi
}

slurm_confirm() {
  local prompt="$1"
  local answer
  slurm_read_tty "${prompt}" answer

  case "${answer}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------------------
# Role / host
# ------------------------------------------------------------------------------

slurm_detect_role() {
  log_section "Detecting Slurm Node Role"

  SHORT_HOST="$(hostname -s)"

  case "${SHORT_HOST}" in
    "${MASTER_HOST}") NODE_ROLE="master" ;;
    "${COMPUTE_HOST}") NODE_ROLE="compute" ;;
    *)
      log_warn "Unknown hostname: ${SHORT_HOST}"
      slurm_read_tty "Enter role manually [master/compute]: " NODE_ROLE
      [[ "${NODE_ROLE}" == "master" || "${NODE_ROLE}" == "compute" ]] || {
        log_error "Invalid role: ${NODE_ROLE}"
        return 1
      }
      ;;
  esac

  log_ok "Node role: ${NODE_ROLE}"
}

slurm_validate_hostname() {
  log_section "Validating Hostname"
  log_info "hostname -s: $(hostname -s)"
  log_info "hostname -f: $(hostname -f 2>/dev/null || hostname)"
}

slurm_configure_hosts() {
  log_section "Configuring /etc/hosts"

  cp -a /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d%H%M%S)" || true

  sed -i "/[[:space:]]${MASTER_HOST}\$/d" /etc/hosts || true
  sed -i "/[[:space:]]${COMPUTE_HOST}\$/d" /etc/hosts || true

  cat >> /etc/hosts <<EOF

# CAPAC Slurm cluster nodes
${MASTER_IP} ${MASTER_HOST}
${COMPUTE_IP} ${COMPUTE_HOST}
EOF

  getent hosts "${MASTER_HOST}" | tee -a "${LOG_FILE}" || true
  getent hosts "${COMPUTE_HOST}" | tee -a "${LOG_FILE}" || true

  log_ok "/etc/hosts configured."
}

# ------------------------------------------------------------------------------
# Packages
# ------------------------------------------------------------------------------

slurm_install_packages() {
  log_section "Installing Slurm Stack Packages"

  dnf install -y epel-release dnf-plugins-core yum-utils || true
  dnf config-manager --set-enabled powertools 2>/dev/null || true
  dnf config-manager --set-enabled PowerTools 2>/dev/null || true
  dnf config-manager --set-enabled crb 2>/dev/null || true
  dnf makecache -y || true

  dnf install -y \
    munge munge-libs munge-devel \
    environment-modules acl \
    hwloc hwloc-libs \
    numactl numactl-libs \
    pmix pmix-devel \
    openmpi openmpi-devel \
    mariadb mariadb-server mariadb-devel \
    perl perl-DBI perl-DBD-MySQL \
    python3 python3-pip \
    jq rsync openssh-clients openssh-server \
    which wget curl tar gzip openssl || true

  dnf install -y \
    slurm \
    slurm-slurmctld \
    slurm-slurmd \
    slurm-slurmdbd \
    slurm-perlapi \
    slurm-devel || {
      log_warn "Some Slurm RPMs failed to install. Check EPEL/PowerTools/CRB."
    }

  command -v slurmd >/dev/null 2>&1 || {
    log_error "slurmd not found. Slurm packages missing."
    return 1
  }

  command -v munged >/dev/null 2>&1 || {
    log_error "munged not found. Munge package missing."
    return 1
  }

  log_ok "Package installation completed."
}

# ------------------------------------------------------------------------------
# Users / groups / dirs / ACLs
# ------------------------------------------------------------------------------

slurm_create_users_groups_dirs() {
  log_section "Creating Users, HPC Group, Directories and ACLs"

  getent group "${HPC_GROUP}" >/dev/null 2>&1 || groupadd "${HPC_GROUP}"

  if ! id "${SLURM_USER}" >/dev/null 2>&1; then
    useradd --system --home /var/lib/slurm --shell /sbin/nologin "${SLURM_USER}" || true
  fi

  if ! id "${RUN_USER}" >/dev/null 2>&1; then
    log_warn "Run user ${RUN_USER} missing. Creating user."
    useradd -m -s /bin/bash "${RUN_USER}"
    passwd "${RUN_USER}"
  fi

  usermod -aG "${HPC_GROUP}" "${RUN_USER}" || true
  usermod -aG "${HPC_GROUP}" "${SLURM_USER}" || true

  mkdir -p \
    /etc/slurm \
    /var/lib/slurm \
    /var/spool/slurmctld \
    /var/spool/slurmd \
    /var/log/slurm \
    "${SHARED_APP_PATH}" \
    "${MODULEFILES_PATH}" \
    "${SHARED_DATA_PATH}" \
    "${SHARED_SCRATCH_PATH}"

  chown -R "${SLURM_USER}:${HPC_GROUP}" /etc/slurm /var/lib/slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm
  chmod 755 /etc/slurm
  chmod 775 /var/lib/slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm

  chown -R root:"${HPC_GROUP}" "${SHARED_APP_PATH}" "${MODULEFILES_PATH}"
  chown -R "${RUN_USER}:${HPC_GROUP}" "${SHARED_DATA_PATH}" "${SHARED_SCRATCH_PATH}"

  chmod 2775 "${SHARED_APP_PATH}" "${MODULEFILES_PATH}" "${SHARED_DATA_PATH}"
  chmod 2777 "${SHARED_SCRATCH_PATH}"

  if command -v setfacl >/dev/null 2>&1; then
    setfacl -R -m g:"${HPC_GROUP}":rwx "${SHARED_APP_PATH}" "${MODULEFILES_PATH}" "${SHARED_DATA_PATH}" "${SHARED_SCRATCH_PATH}" || true
    setfacl -R -d -m g:"${HPC_GROUP}":rwx "${SHARED_APP_PATH}" "${MODULEFILES_PATH}" "${SHARED_DATA_PATH}" "${SHARED_SCRATCH_PATH}" || true
    setfacl -R -m u:"${RUN_USER}":rwx /var/log/slurm /var/spool/slurmd || true
    setfacl -R -m u:"${SLURM_USER}":rwx /var/log/slurm /var/spool/slurmd /var/spool/slurmctld || true
  fi

  log_ok "Users, groups, directories and ACLs configured."
}

# ------------------------------------------------------------------------------
# Future user helper
# ------------------------------------------------------------------------------

slurm_install_hpc_user_helper() {
  log_section "Installing Future HPC User Helper"

  cat > /usr/local/sbin/capac-add-hpc-user <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

HPC_GROUP="${HPC_GROUP}"
SHARED_APP_PATH="${SHARED_APP_PATH}"
MODULEFILES_PATH="${MODULEFILES_PATH}"
SHARED_DATA_PATH="${SHARED_DATA_PATH}"
SHARED_SCRATCH_PATH="${SHARED_SCRATCH_PATH}"

if [[ "\${EUID}" -ne 0 ]]; then
  echo "Run as root or sudo."
  exit 1
fi

if [[ "\${1:-}" == "" ]]; then
  echo "Usage: sudo capac-add-hpc-user <username>"
  exit 1
fi

NEW_USER="\$1"

getent group "\${HPC_GROUP}" >/dev/null 2>&1 || groupadd "\${HPC_GROUP}"

if ! id "\${NEW_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "\${NEW_USER}"
  passwd "\${NEW_USER}"
else
  echo "User exists: \${NEW_USER}"
fi

usermod -aG "\${HPC_GROUP}" "\${NEW_USER}"

mkdir -p "\${SHARED_APP_PATH}" "\${MODULEFILES_PATH}" "\${SHARED_DATA_PATH}" "\${SHARED_SCRATCH_PATH}"

chown -R root:"\${HPC_GROUP}" "\${SHARED_APP_PATH}" "\${MODULEFILES_PATH}"
chown -R root:"\${HPC_GROUP}" "\${SHARED_DATA_PATH}" "\${SHARED_SCRATCH_PATH}"

chmod 2775 "\${SHARED_APP_PATH}" "\${MODULEFILES_PATH}" "\${SHARED_DATA_PATH}"
chmod 2777 "\${SHARED_SCRATCH_PATH}"

if command -v setfacl >/dev/null 2>&1; then
  setfacl -R -m g:"\${HPC_GROUP}":rwx "\${SHARED_APP_PATH}" "\${MODULEFILES_PATH}" "\${SHARED_DATA_PATH}" "\${SHARED_SCRATCH_PATH}" || true
  setfacl -R -d -m g:"\${HPC_GROUP}":rwx "\${SHARED_APP_PATH}" "\${MODULEFILES_PATH}" "\${SHARED_DATA_PATH}" "\${SHARED_SCRATCH_PATH}" || true
  setfacl -R -m u:"\${NEW_USER}":rwx "\${SHARED_DATA_PATH}" "\${SHARED_SCRATCH_PATH}" || true
fi

cat > /etc/profile.d/capac-hpc-user-path.sh <<'PROFILEEOF'
# CAPAC HPC user environment
if [[ -f /etc/profile.d/modules.sh ]]; then
  source /etc/profile.d/modules.sh
fi

if command -v module >/dev/null 2>&1; then
  module use /opt/modulefiles >/dev/null 2>&1 || true
fi
PROFILEEOF

echo "User \${NEW_USER} is ready for HPC/Slurm jobs."
echo "Ask user to logout/login once to inherit hpc group membership."
EOF

  chmod 755 /usr/local/sbin/capac-add-hpc-user
  chown root:root /usr/local/sbin/capac-add-hpc-user

  log_ok "Installed: /usr/local/sbin/capac-add-hpc-user"
}

# ------------------------------------------------------------------------------
# Munge
# ------------------------------------------------------------------------------

slurm_configure_munge() {
  log_section "Configuring Munge"

  dnf install -y munge munge-libs munge-devel || true

  systemctl stop munge 2>/dev/null || true

  rm -f /run/munge/munge.socket.2 /run/munge/munged.pid 2>/dev/null || true
  rm -f /var/run/munge/munge.socket.2 /var/run/munge/munged.pid 2>/dev/null || true

  mkdir -p /etc/munge /var/lib/munge /var/log/munge /run/munge

  if [[ "${NODE_ROLE}" == "master" ]]; then
    if [[ ! -s /etc/munge/munge.key ]]; then
      log_info "Generating Munge key using /dev/urandom."
      dd if=/dev/urandom of=/etc/munge/munge.key bs=1024 count=1 status=none
    else
      log_ok "Munge key already exists."
    fi
  else
    [[ -s /etc/munge/munge.key ]] || log_warn "Munge key missing on compute node."
  fi

  chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /run/munge || true

  chmod 0700 /etc/munge
  chmod 0711 /var/lib/munge
  chmod 0700 /var/log/munge
  chmod 0755 /run/munge
  chmod 0400 /etc/munge/munge.key 2>/dev/null || true

  systemctl daemon-reload
  systemctl enable munge
  systemctl restart munge

  sleep 2

  if ! systemctl is-active munge >/dev/null 2>&1; then
    log_error "Munge failed to start."
    systemctl status munge --no-pager -l || true
    journalctl -u munge -n 80 --no-pager || true
    return 1
  fi

  if ! munge -n | unmunge >/dev/null 2>&1; then
    log_error "Munge validation failed."
    systemctl status munge --no-pager -l || true
    journalctl -u munge -n 80 --no-pager || true
    return 1
  fi

  log_ok "Munge configured and validated."
}

# ------------------------------------------------------------------------------
# MariaDB accounting
# ------------------------------------------------------------------------------

slurm_configure_mariadb_if_master() {
  [[ "${NODE_ROLE}" == "master" ]] || {
    log_info "Skipping MariaDB on compute node."
    return 0
  }

  log_section "Configuring MariaDB Slurm Accounting"

  systemctl enable --now mariadb

  mkdir -p /etc/my.cnf.d

  cat > /etc/my.cnf.d/99-slurm.cnf <<'EOF'
[mysqld]
innodb_buffer_pool_size=1024M
innodb_lock_wait_timeout=900
max_allowed_packet=64M
bind-address=127.0.0.1
EOF

  systemctl restart mariadb

  mkdir -p /etc/slurm

  if [[ ! -f "${SLURM_DB_PASS_FILE}" ]]; then
    openssl rand -base64 24 > "${SLURM_DB_PASS_FILE}"
    chmod 600 "${SLURM_DB_PASS_FILE}"
  fi

  SLURM_DB_PASS="$(cat "${SLURM_DB_PASS_FILE}")"

  mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS ${SLURM_DB_NAME};
CREATE USER IF NOT EXISTS '${SLURM_DB_USER}'@'localhost' IDENTIFIED BY '${SLURM_DB_PASS}';
GRANT ALL PRIVILEGES ON ${SLURM_DB_NAME}.* TO '${SLURM_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

  log_ok "MariaDB accounting configured."
}

# ------------------------------------------------------------------------------
# Slurm config
# ------------------------------------------------------------------------------

slurm_write_configs() {
  log_section "Writing Slurm Configuration"

  local slurm_conf="/etc/slurm/slurm.conf"
  local cgroup_conf="/etc/slurm/cgroup.conf"
  local slurmdbd_conf="/etc/slurm/slurmdbd.conf"

  [[ -f "${slurm_conf}" ]] && cp -a "${slurm_conf}" "${slurm_conf}.bak.$(date +%Y%m%d%H%M%S)"
  [[ -f "${cgroup_conf}" ]] && cp -a "${cgroup_conf}" "${cgroup_conf}.bak.$(date +%Y%m%d%H%M%S)"
  [[ -f "${slurmdbd_conf}" ]] && cp -a "${slurmdbd_conf}" "${slurmdbd_conf}.bak.$(date +%Y%m%d%H%M%S)"

  cat > "${slurm_conf}" <<EOF
ClusterName=${CLUSTER_NAME}
SlurmctldHost=${MASTER_HOST}(${MASTER_IP})

SlurmUser=${SLURM_USER}
AuthType=auth/munge
CryptoType=crypto/munge
MpiDefault=pmix

SlurmctldPort=6817
SlurmdPort=6818

StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd

SlurmctldPidFile=/run/slurmctld.pid
SlurmdPidFile=/run/slurmd.pid

SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmctldDebug=info
SlurmdDebug=info

ReturnToService=2
InactiveLimit=0
KillWait=30
MinJobAge=300
SlurmctldTimeout=120
SlurmdTimeout=300
Waittime=0

SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

TaskPlugin=task/cgroup,task/affinity
ProctrackType=proctrack/cgroup
JobAcctGatherType=jobacct_gather/cgroup
JobAcctGatherFrequency=30

AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=${MASTER_HOST}
AccountingStoragePort=6819
AccountingStorageTRES=gres/gpu,cpu,mem,node,billing,fs/disk,vmem,pages

PriorityType=priority/multifactor
LaunchParameters=use_interactive_step

NodeName=${MASTER_HOST} NodeAddr=${MASTER_IP} CPUs=${NODE_CPUS} RealMemory=${NODE_REALMEMORY} Sockets=1 CoresPerSocket=${NODE_CPUS} ThreadsPerCore=1 State=UNKNOWN
NodeName=${COMPUTE_HOST} NodeAddr=${COMPUTE_IP} CPUs=${NODE_CPUS} RealMemory=${NODE_REALMEMORY} Sockets=1 CoresPerSocket=${NODE_CPUS} ThreadsPerCore=1 State=UNKNOWN

PartitionName=${PARTITION_NAME} Nodes=${MASTER_HOST},${COMPUTE_HOST} Default=YES MaxTime=INFINITE State=UP OverSubscribe=NO
EOF

  cat > "${cgroup_conf}" <<'EOF'
CgroupAutomount=yes
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedRAMSpace=100
AllowedSwapSpace=0
MaxRAMPercent=100
MaxSwapPercent=0
MinRAMSpace=30
EOF

  if [[ "${NODE_ROLE}" == "master" ]]; then
    SLURM_DB_PASS="$(cat "${SLURM_DB_PASS_FILE}")"

    cat > "${slurmdbd_conf}" <<EOF
AuthType=auth/munge
DbdHost=${MASTER_HOST}
DbdPort=6819
SlurmUser=${SLURM_USER}
DebugLevel=info
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/run/slurmdbd.pid

StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StorageLoc=${SLURM_DB_NAME}
StorageUser=${SLURM_DB_USER}
StoragePass=${SLURM_DB_PASS}
EOF

    chmod 600 "${slurmdbd_conf}"
    chown "${SLURM_USER}:${HPC_GROUP}" "${slurmdbd_conf}" || true
  fi

  chmod 644 "${slurm_conf}" "${cgroup_conf}"
  chown -R "${SLURM_USER}:${HPC_GROUP}" /etc/slurm /var/log/slurm /var/spool/slurmctld /var/spool/slurmd

  log_ok "Slurm configs written."
}

# ------------------------------------------------------------------------------
# Environment Modules
# ------------------------------------------------------------------------------

slurm_configure_environment_modules() {
  log_section "Configuring Environment Modules"

  mkdir -p "${MODULEFILES_PATH}/openmpi" "${MODULEFILES_PATH}/intel-mpi"

  cat > /etc/profile.d/capac-modules.sh <<EOF
if [[ -f /etc/profile.d/modules.sh ]]; then
  source /etc/profile.d/modules.sh
fi

if command -v module >/dev/null 2>&1; then
  module use ${MODULEFILES_PATH} >/dev/null 2>&1 || true
fi
EOF

  cat > "${MODULEFILES_PATH}/openmpi/rocky8" <<'EOF'
#%Module1.0#####################################################################
proc ModulesHelp { } {
    puts stderr "Loads OpenMPI from Rocky/EPEL packages."
}
module-whatis "OpenMPI for CAPAC Rocky 8 CAE/HPC cluster"
prepend-path PATH /usr/lib64/openmpi/bin
prepend-path LD_LIBRARY_PATH /usr/lib64/openmpi/lib
prepend-path MANPATH /usr/share/man
setenv MPI_HOME /usr/lib64/openmpi
setenv OMPI_MCA_btl self,vader,tcp
EOF

  chown -R root:"${HPC_GROUP}" "${MODULEFILES_PATH}"
  chmod -R g+rwX "${MODULEFILES_PATH}"
  chmod 2775 "${MODULEFILES_PATH}"

  log_ok "Environment Modules configured."
}

# ------------------------------------------------------------------------------
# Intel MPI module
# ------------------------------------------------------------------------------

slurm_configure_intel_mpi_module() {
  log_section "Configuring Intel MPI Modulefile"

  if [[ "${INSTALL_INTEL_MPI}" == "ask" && "${NODE_ROLE}" == "master" ]]; then
    if slurm_confirm "Intel oneAPI is not installed. Install Intel MPI packages now? [y/N]: "; then
      INSTALL_INTEL_MPI="yes"
    else
      INSTALL_INTEL_MPI="no"
    fi
  fi

  if [[ "${INSTALL_INTEL_MPI}" == "yes" ]]; then
    log_info "Adding Intel oneAPI repo."

    cat > /etc/yum.repos.d/intel-oneapi.repo <<'EOF'
[oneAPI]
name=Intel oneAPI repository
baseurl=https://yum.repos.intel.com/oneapi
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB
EOF

    dnf makecache --disablerepo="*" --enablerepo="oneAPI" -y || {
      log_warn "Intel oneAPI repo refresh failed. Skipping Intel MPI install."
      INSTALL_INTEL_MPI="no"
    }

    if [[ "${INSTALL_INTEL_MPI}" == "yes" ]]; then
      dnf install -y intel-oneapi-mpi intel-oneapi-mpi-devel || {
        log_warn "Intel MPI install failed. Continuing with modulefile only."
      }
    fi
  fi

  mkdir -p "${MODULEFILES_PATH}/intel-mpi"

  cat > "${MODULEFILES_PATH}/intel-mpi/oneapi" <<EOF
#%Module1.0#####################################################################
proc ModulesHelp { } {
    puts stderr "Loads Intel MPI from Intel oneAPI if installed under ${INTEL_ONEAPI_ROOT}."
}
module-whatis "Intel MPI from oneAPI"
set mpi_root ${INTEL_ONEAPI_ROOT}/mpi/latest
if { ! [file isdirectory \$mpi_root] } {
    puts stderr "WARNING: Intel MPI not found at \$mpi_root"
}
prepend-path PATH \$mpi_root/bin
prepend-path LD_LIBRARY_PATH \$mpi_root/lib
prepend-path MANPATH \$mpi_root/share/man
setenv I_MPI_ROOT \$mpi_root
setenv MPI_HOME \$mpi_root
setenv I_MPI_FABRICS shm:tcp
setenv I_MPI_PIN 1
setenv I_MPI_PIN_DOMAIN core
EOF

  chown -R root:"${HPC_GROUP}" "${MODULEFILES_PATH}/intel-mpi"
  chmod -R g+rwX "${MODULEFILES_PATH}/intel-mpi"

  log_ok "Intel MPI modulefile configured."
}

# ------------------------------------------------------------------------------
# Root SSH and sync
# ------------------------------------------------------------------------------

slurm_setup_root_ssh_if_master() {
  [[ "${NODE_ROLE}" == "master" ]] || return 0

  log_section "Checking Root SSH to Compute"

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh

  if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
  fi

  if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"${COMPUTE_HOST}" "hostname -s" >/dev/null 2>&1; then
    log_ok "Passwordless root SSH works."
    return 0
  fi

  log_warn "Passwordless root SSH not ready."

  if slurm_confirm "Setup root SSH key copy to ${COMPUTE_HOST}? [y/N]: "; then
    ssh-copy-id -o StrictHostKeyChecking=no root@"${COMPUTE_HOST}" || true
  fi
}

slurm_sync_to_compute_if_master() {
  [[ "${NODE_ROLE}" == "master" ]] || return 0

  log_section "Syncing Slurm/Munge/Modules to Compute"

  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"${COMPUTE_HOST}" "hostname -s" >/dev/null 2>&1; then
    log_warn "Skipping sync. Root SSH not ready."
    return 0
  fi

  ssh root@"${COMPUTE_HOST}" "
    mkdir -p /etc/munge /etc/slurm /var/lib/munge /var/log/munge /run/munge /var/log/slurm /var/spool/slurmd ${SHARED_APP_PATH} ${MODULEFILES_PATH} ${SHARED_DATA_PATH} ${SHARED_SCRATCH_PATH}
    getent group ${HPC_GROUP} >/dev/null 2>&1 || groupadd ${HPC_GROUP}
    id ${RUN_USER} >/dev/null 2>&1 && usermod -aG ${HPC_GROUP} ${RUN_USER} || true
    id ${SLURM_USER} >/dev/null 2>&1 && usermod -aG ${HPC_GROUP} ${SLURM_USER} || true
  "

  scp /etc/munge/munge.key root@"${COMPUTE_HOST}":/etc/munge/munge.key
  rsync -av /etc/slurm/slurm.conf /etc/slurm/cgroup.conf root@"${COMPUTE_HOST}":/etc/slurm/
  rsync -av "${MODULEFILES_PATH}/" root@"${COMPUTE_HOST}":"${MODULEFILES_PATH}/"
  rsync -av /etc/profile.d/capac-modules.sh root@"${COMPUTE_HOST}":/etc/profile.d/capac-modules.sh
  rsync -av /usr/local/sbin/capac-add-hpc-user root@"${COMPUTE_HOST}":/usr/local/sbin/capac-add-hpc-user

  ssh root@"${COMPUTE_HOST}" "
    rm -f /run/munge/munge.socket.2 /run/munge/munged.pid /var/run/munge/munge.socket.2 /var/run/munge/munged.pid 2>/dev/null || true

    chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /run/munge 2>/dev/null || true
    chmod 0700 /etc/munge
    chmod 0711 /var/lib/munge
    chmod 0700 /var/log/munge
    chmod 0755 /run/munge
    chmod 0400 /etc/munge/munge.key

    chown -R ${SLURM_USER}:${HPC_GROUP} /etc/slurm /var/log/slurm /var/spool/slurmd 2>/dev/null || true
    chmod 775 /var/log/slurm /var/spool/slurmd 2>/dev/null || true

    chown -R root:${HPC_GROUP} ${SHARED_APP_PATH} ${MODULEFILES_PATH}
    chown -R ${RUN_USER}:${HPC_GROUP} ${SHARED_DATA_PATH} ${SHARED_SCRATCH_PATH}
    chmod 2775 ${SHARED_APP_PATH} ${MODULEFILES_PATH} ${SHARED_DATA_PATH}
    chmod 2777 ${SHARED_SCRATCH_PATH}

    if command -v setfacl >/dev/null 2>&1; then
      setfacl -R -m g:${HPC_GROUP}:rwx ${SHARED_APP_PATH} ${MODULEFILES_PATH} ${SHARED_DATA_PATH} ${SHARED_SCRATCH_PATH} || true
      setfacl -R -d -m g:${HPC_GROUP}:rwx ${SHARED_APP_PATH} ${MODULEFILES_PATH} ${SHARED_DATA_PATH} ${SHARED_SCRATCH_PATH} || true
    fi

    chmod 755 /usr/local/sbin/capac-add-hpc-user || true
    systemctl enable munge slurmd || true
    systemctl restart munge || true
    systemctl restart slurmd || true
  "

  log_ok "Compute node synced."
}

# ------------------------------------------------------------------------------
# Services and boot persistence
# ------------------------------------------------------------------------------

slurm_enable_services() {
  log_section "Enabling Slurm Services"

  systemctl enable munge
  systemctl restart munge

  sleep 2

  if ! munge -n | unmunge >/dev/null 2>&1; then
    log_error "Munge validation failed. Not starting Slurm."
    systemctl status munge --no-pager -l || true
    journalctl -u munge -n 80 --no-pager || true
    return 1
  fi

  if [[ "${NODE_ROLE}" == "master" ]]; then
    systemctl enable --now mariadb

    systemctl enable slurmdbd
    systemctl restart slurmdbd
    sleep 3

    if ! systemctl is-active slurmdbd >/dev/null 2>&1; then
      log_error "slurmdbd failed."
      systemctl status slurmdbd --no-pager -l || true
      journalctl -u slurmdbd -n 80 --no-pager || true
      return 1
    fi

    systemctl enable slurmctld
    systemctl restart slurmctld
    sleep 3

    if ! systemctl is-active slurmctld >/dev/null 2>&1; then
      log_error "slurmctld failed."
      systemctl status slurmctld --no-pager -l || true
      journalctl -u slurmctld -n 80 --no-pager || true
      return 1
    fi
  fi

  systemctl enable slurmd
  systemctl restart slurmd
  sleep 2

  if ! systemctl is-active slurmd >/dev/null 2>&1; then
    log_error "slurmd failed."
    systemctl status slurmd --no-pager -l || true
    journalctl -u slurmd -n 80 --no-pager || true
    return 1
  fi

  log_ok "Slurm services enabled and active."
}

slurm_enable_boot_persistence() {
  log_section "Enabling Reboot Persistence"

  systemctl daemon-reload
  systemctl enable munge

  if [[ "${NODE_ROLE}" == "master" ]]; then
    systemctl enable mariadb
    systemctl enable slurmdbd
    systemctl enable slurmctld
  fi

  systemctl enable slurmd

  cat > /etc/systemd/system/slurm-recover.service <<'EOF'
[Unit]
Description=CAPAC Slurm Recovery After Boot
After=network-online.target munge.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -lc 'systemctl restart munge; sleep 2; systemctl restart slurmd; if systemctl list-unit-files slurmctld.service >/dev/null 2>&1; then systemctl restart slurmdbd || true; sleep 2; systemctl restart slurmctld || true; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable slurm-recover.service

  log_ok "Boot persistence enabled."
}

# ------------------------------------------------------------------------------
# Accounting / tests / summary
# ------------------------------------------------------------------------------

slurm_register_accounting_if_master() {
  [[ "${NODE_ROLE}" == "master" ]] || return 0

  log_section "Registering Slurm Accounting Cluster"

  if ! munge -n | unmunge >/dev/null 2>&1; then
    log_error "Munge unhealthy. Skipping accounting registration."
    return 1
  fi

  if command -v sacctmgr >/dev/null 2>&1; then
    sacctmgr -i add cluster "${CLUSTER_NAME}" || true
    sacctmgr show cluster -P | tee -a "${LOG_FILE}" || true
  else
    log_warn "sacctmgr not available."
  fi
}

slurm_create_test_jobs_if_master() {
  [[ "${NODE_ROLE}" == "master" ]] || return 0

  log_section "Creating Slurm Test Jobs"

  mkdir -p /opt/slurm-tests

  cat > /opt/slurm-tests/hostname-test.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=capac-hostname
#SBATCH --partition=${PARTITION_NAME}
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:05:00
#SBATCH --output=${SHARED_SCRATCH_PATH}/capac-hostname-%j.out

echo "Job ID: \${SLURM_JOB_ID}"
echo "Nodes: \${SLURM_JOB_NODELIST}"
srun hostname
EOF

  cat > /opt/slurm-tests/cpu-test.sbatch <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=capac-cpu-test
#SBATCH --partition=${PARTITION_NAME}
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=4
#SBATCH --time=00:05:00
#SBATCH --output=${SHARED_SCRATCH_PATH}/capac-cpu-test-%j.out

echo "Job ID: \${SLURM_JOB_ID}"
echo "Node: \$(hostname)"
lscpu | egrep 'CPU\\(s\\)|Thread|Core|Socket|NUMA'
srun bash -c 'echo rank=\${SLURM_PROCID} host=\$(hostname)'
EOF

  chmod +x /opt/slurm-tests/*.sbatch
  chown -R root:"${HPC_GROUP}" /opt/slurm-tests
  chmod -R 775 /opt/slurm-tests

  log_ok "Test jobs created."
}

slurm_summary() {
  log_section "Slurm Cluster Summary"

  log_info "Role      : ${NODE_ROLE}"
  log_info "Cluster   : ${CLUSTER_NAME}"
  log_info "Partition : ${PARTITION_NAME}"
  log_info "Nodes     : ${MASTER_HOST}, ${COMPUTE_HOST}"

  log_info "Munge:"
  systemctl is-active munge | tee -a "${LOG_FILE}" || true
  munge -n | unmunge | head -10 | tee -a "${LOG_FILE}" || true

  log_info "Slurm services:"
  systemctl is-active slurmctld 2>/dev/null | tee -a "${LOG_FILE}" || true
  systemctl is-active slurmdbd 2>/dev/null | tee -a "${LOG_FILE}" || true
  systemctl is-active slurmd 2>/dev/null | tee -a "${LOG_FILE}" || true

  if [[ "${NODE_ROLE}" == "master" ]]; then
    scontrol ping | tee -a "${LOG_FILE}" || true
    sinfo -Nel | tee -a "${LOG_FILE}" || true
    sinfo | tee -a "${LOG_FILE}" || true
    sacctmgr show cluster -P | tee -a "${LOG_FILE}" || true
  fi

  log_info "Environment Modules:"
  if [[ -f /etc/profile.d/modules.sh ]]; then
    # shellcheck source=/dev/null
    source /etc/profile.d/modules.sh
  fi
  command -v module | tee -a "${LOG_FILE}" || true
  find "${MODULEFILES_PATH}" -maxdepth 3 -type f | tee -a "${LOG_FILE}" || true

  log_info "User and directory access:"
  id "${RUN_USER}" | tee -a "${LOG_FILE}" || true
  id "${SLURM_USER}" | tee -a "${LOG_FILE}" || true
  getent group "${HPC_GROUP}" | tee -a "${LOG_FILE}" || true

  ls -ld \
    "${SHARED_APP_PATH}" \
    "${MODULEFILES_PATH}" \
    "${SHARED_DATA_PATH}" \
    "${SHARED_SCRATCH_PATH}" \
    /var/log/slurm \
    /var/spool/slurmd \
    /var/spool/slurmctld 2>/dev/null | tee -a "${LOG_FILE}" || true

  log_info "Future user:"
  log_info "  sudo capac-add-hpc-user <username>"

  log_ok "Slurm summary completed."
}