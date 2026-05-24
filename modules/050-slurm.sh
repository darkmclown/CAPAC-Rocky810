#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# CAPAC Rocky 8.10 CAE/HPC Bootstrap
# File: modules/050-slurm.sh
#
# Purpose:
#   Configure Slurm + Munge + MariaDB accounting + Environment Modules + MPI
#   for a 2-node CAE/HPC CFD cluster.
#
# Cluster:
#   Master/controller/compute : cae-01 / 192.168.2.131
#   Compute node              : cae-03 / 192.168.2.133
#
# Design:
#   - cae-01 runs slurmctld, slurmdbd, MariaDB, munge, slurmd
#   - cae-03 runs munge and slurmd
#   - Both nodes can run solver jobs
#   - Partition: cfd
#   - CPUs per node: 40
#   - RAM per node: 380 GB
#   - Accounting: MariaDB
#   - Module system: environment-modules
#   - Modulefiles path: /opt/modulefiles
#   - Scratch path: /home/data/scratch
#
# Required function:
#   slurm_main()
# ==============================================================================

slurm_main() {
  log_section "Slurm + Munge + MariaDB + Environment Modules"

  slurm_set_defaults
  slurm_detect_role
  slurm_validate_hostname
  slurm_configure_hosts
  slurm_install_packages
  slurm_create_users_and_dirs
  slurm_configure_munge
  slurm_configure_mariadb_if_master
  slurm_write_configs
  slurm_configure_environment_modules
  slurm_configure_intel_mpi_module
  slurm_setup_root_ssh_if_master
  slurm_sync_to_compute_if_master
  slurm_enable_services
  slurm_register_accounting_if_master
  slurm_create_test_jobs_if_master
  slurm_summary

  log_ok "Slurm + Munge + MariaDB + Environment Modules completed successfully."
}

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------

slurm_set_defaults() {
  log_section "Loading Slurm Cluster Defaults"

  CLUSTER_NAME="${CLUSTER_NAME:-capac-cfd}"
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
  MUNGE_USER="${MUNGE_USER:-munge}"
  SSH_ADMIN_USER="${SSH_ADMIN_USER:-cadfem}"

  SLURM_DB_NAME="${SLURM_DB_NAME:-slurm_acct_db}"
  SLURM_DB_USER="${SLURM_DB_USER:-slurm}"
  SLURM_DB_PASS_FILE="${SLURM_DB_PASS_FILE:-/etc/slurm/slurmdbd.password}"

  INTEL_ONEAPI_ROOT="${INTEL_ONEAPI_ROOT:-/opt/intel/oneapi}"
  INSTALL_INTEL_MPI="${INSTALL_INTEL_MPI:-ask}"

  log_info "Cluster name      : ${CLUSTER_NAME}"
  log_info "Partition         : ${PARTITION_NAME}"
  log_info "Master            : ${MASTER_HOST} / ${MASTER_IP}"
  log_info "Compute           : ${COMPUTE_HOST} / ${COMPUTE_IP}"
  log_info "Node CPUs         : ${NODE_CPUS}"
  log_info "Node RealMemory   : ${NODE_REALMEMORY} MB"
  log_info "App path          : ${SHARED_APP_PATH}"
  log_info "Data path         : ${SHARED_DATA_PATH}"
  log_info "Scratch path      : ${SHARED_SCRATCH_PATH}"
  log_info "Modulefiles path  : ${MODULEFILES_PATH}"
  log_info "Intel oneAPI root : ${INTEL_ONEAPI_ROOT}"
}

# ------------------------------------------------------------------------------
# Input Helpers
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
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Role Detection
# ------------------------------------------------------------------------------

slurm_detect_role() {
  log_section "Detecting Node Role"

  SHORT_HOST="$(hostname -s)"

  case "${SHORT_HOST}" in
    "${MASTER_HOST}")
      NODE_ROLE="master"
      ;;
    "${COMPUTE_HOST}")
      NODE_ROLE="compute"
      ;;
    *)
      log_warn "Unknown hostname: ${SHORT_HOST}"
      log_warn "Expected ${MASTER_HOST} or ${COMPUTE_HOST}"

      local manual_role
      slurm_read_tty "Enter node role manually [master/compute]: " manual_role

      case "${manual_role}" in
        master|compute)
          NODE_ROLE="${manual_role}"
          ;;
        *)
          log_error "Invalid role: ${manual_role}"
          return 1
          ;;
      esac
      ;;
  esac

  log_ok "Detected node role: ${NODE_ROLE}"
}

slurm_validate_hostname() {
  log_section "Validating Hostname"

  log_info "hostname -s: $(hostname -s)"
  log_info "hostname -f: $(hostname -f 2>/dev/null || hostname)"
}

# ------------------------------------------------------------------------------
# /etc/hosts
# ------------------------------------------------------------------------------

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

  log_ok "/etc/hosts updated."
  getent hosts "${MASTER_HOST}" | tee -a "${LOG_FILE}" || true
  getent hosts "${COMPUTE_HOST}" | tee -a "${LOG_FILE}" || true
}

# ------------------------------------------------------------------------------
# Packages
# ------------------------------------------------------------------------------

slurm_install_packages() {
  log_section "Installing Slurm, Munge, MariaDB, Environment Modules and MPI Packages"

  dnf install -y epel-release dnf-plugins-core yum-utils || true
  dnf config-manager --set-enabled powertools 2>/dev/null || true
  dnf config-manager --set-enabled PowerTools 2>/dev/null || true
  dnf config-manager --set-enabled crb 2>/dev/null || true
  dnf makecache -y || true

  dnf install -y \
    munge \
    munge-libs \
    munge-devel \
    environment-modules \
    hwloc \
    hwloc-libs \
    numactl \
    numactl-libs \
    pmix \
    pmix-devel \
    openmpi \
    openmpi-devel \
    mariadb \
    mariadb-server \
    mariadb-devel \
    perl \
    perl-DBI \
    perl-DBD-MySQL \
    python3 \
    python3-pip \
    jq \
    rsync \
    openssh-clients \
    openssh-server \
    which \
    wget \
    curl \
    tar \
    gzip \
    openssl || true

  dnf install -y \
    slurm \
    slurm-slurmctld \
    slurm-slurmd \
    slurm-slurmdbd \
    slurm-perlapi \
    slurm-devel || {
      log_warn "Some Slurm RPMs failed to install from enabled repositories."
      log_warn "Check EPEL/PowerTools/CRB availability on Rocky 8.10."
    }

  if ! command -v slurmd >/dev/null 2>&1; then
    log_error "slurmd not found after package install. Slurm packages are missing."
    return 1
  fi

  log_ok "Slurm/Munge/MariaDB/environment-modules package installation completed."
}

# ------------------------------------------------------------------------------
# Users and Directories
# ------------------------------------------------------------------------------

slurm_create_users_and_dirs() {
  log_section "Creating Slurm Users and Directories"

  if ! id "${SLURM_USER}" >/dev/null 2>&1; then
    useradd --system --home /var/lib/slurm --shell /sbin/nologin "${SLURM_USER}" || true
    log_ok "Created user: ${SLURM_USER}"
  else
    log_ok "User exists: ${SLURM_USER}"
  fi

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

  chown -R "${SLURM_USER}:${SLURM_USER}" /var/lib/slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm
  chmod 755 /etc/slurm
  chmod 755 "${SHARED_APP_PATH}" "${MODULEFILES_PATH}" "${SHARED_DATA_PATH}"
  chmod 1777 "${SHARED_SCRATCH_PATH}"

  log_ok "Slurm directories and shared paths are ready."
}

# ------------------------------------------------------------------------------
# Munge
# ------------------------------------------------------------------------------

slurm_configure_munge() {
  log_section "Configuring Munge"

  mkdir -p /etc/munge /var/lib/munge /var/log/munge /run/munge

  if [[ "${NODE_ROLE}" == "master" ]]; then
    if [[ ! -f /etc/munge/munge.key ]]; then
      log_info "Generating Munge key on master."
      /usr/sbin/create-munge-key -r || dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key
    else
      log_ok "Munge key already exists on master."
    fi
  else
    if [[ ! -f /etc/munge/munge.key ]]; then
      log_warn "Munge key missing on compute node."
      log_warn "It must be copied from ${MASTER_HOST}:/etc/munge/munge.key"
    fi
  fi

  chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /run/munge || true
  chmod 0700 /etc/munge /var/lib/munge /var/log/munge /run/munge || true
  chmod 0400 /etc/munge/munge.key 2>/dev/null || true

  systemctl enable --now munge
  systemctl restart munge

  log_ok "Munge configured and started."
}

# ------------------------------------------------------------------------------
# MariaDB Accounting on Master
# ------------------------------------------------------------------------------

slurm_configure_mariadb_if_master() {
  if [[ "${NODE_ROLE}" != "master" ]]; then
    log_info "Skipping MariaDB accounting setup on compute node."
    return 0
  fi

  log_section "Configuring MariaDB for Slurm Accounting"

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

  if [[ ! -f "${SLURM_DB_PASS_FILE}" ]]; then
    mkdir -p /etc/slurm
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

  log_ok "MariaDB Slurm accounting database configured."
}

# ------------------------------------------------------------------------------
# Slurm Configs
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
# ==============================================================================
# CAPAC Slurm Configuration
# ==============================================================================

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

# Nodes
NodeName=${MASTER_HOST} NodeAddr=${MASTER_IP} CPUs=${NODE_CPUS} RealMemory=${NODE_REALMEMORY} Sockets=1 CoresPerSocket=${NODE_CPUS} ThreadsPerCore=1 State=UNKNOWN
NodeName=${COMPUTE_HOST} NodeAddr=${COMPUTE_IP} CPUs=${NODE_CPUS} RealMemory=${NODE_REALMEMORY} Sockets=1 CoresPerSocket=${NODE_CPUS} ThreadsPerCore=1 State=UNKNOWN

# CFD partition
PartitionName=${PARTITION_NAME} Nodes=${MASTER_HOST},${COMPUTE_HOST} Default=YES MaxTime=INFINITE State=UP OverSubscribe=NO
EOF

  cat > "${cgroup_conf}" <<'EOF'
# ==============================================================================
# CAPAC Slurm Cgroup Configuration
# ==============================================================================

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
# ==============================================================================
# CAPAC SlurmDBD Configuration
# ==============================================================================

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
    chown "${SLURM_USER}:${SLURM_USER}" "${slurmdbd_conf}" || true
  fi

  chmod 644 "${slurm_conf}" "${cgroup_conf}"
  chown -R "${SLURM_USER}:${SLURM_USER}" /etc/slurm /var/log/slurm /var/spool/slurmctld /var/spool/slurmd

  log_ok "Slurm configuration written."
}

# ------------------------------------------------------------------------------
# Environment Modules
# ------------------------------------------------------------------------------

slurm_configure_environment_modules() {
  log_section "Configuring Environment Modules"

  mkdir -p "${MODULEFILES_PATH}"
  chmod 755 "${MODULEFILES_PATH}"

  cat > /etc/profile.d/capac-modules.sh <<EOF
# CAPAC Environment Modules path

if [[ -f /etc/profile.d/modules.sh ]]; then
  source /etc/profile.d/modules.sh
fi

if command -v module >/dev/null 2>&1; then
  module use ${MODULEFILES_PATH} >/dev/null 2>&1 || true
fi
EOF

  mkdir -p "${MODULEFILES_PATH}/openmpi"

  cat > "${MODULEFILES_PATH}/openmpi/rocky8" <<'EOF'
#%Module1.0#####################################################################
##
## OpenMPI module for CAPAC Rocky 8 CAE/HPC cluster
##

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

  log_ok "Environment Modules configured."
  log_info "Modulefiles path: ${MODULEFILES_PATH}"
}

# ------------------------------------------------------------------------------
# Intel MPI Modulefile
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
    log_info "Adding Intel oneAPI repository and installing Intel MPI packages."

    rpm --import https://yum.repos.intel.com/oneapi/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB || true

    cat > /etc/yum.repos.d/intel-oneapi.repo <<'EOF'
[oneAPI]
name=Intel oneAPI repository
baseurl=https://yum.repos.intel.com/oneapi
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://yum.repos.intel.com/oneapi/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB
EOF

    dnf makecache -y || true
    dnf install -y intel-oneapi-mpi intel-oneapi-mpi-devel || {
      log_warn "Intel MPI package install failed. Modulefile will still be created."
    }
  fi

  mkdir -p "${MODULEFILES_PATH}/intel-mpi"

  cat > "${MODULEFILES_PATH}/intel-mpi/oneapi" <<EOF
#%Module1.0#####################################################################
##
## Intel MPI module for CAPAC CAE/HPC cluster
##

proc ModulesHelp { } {
    puts stderr "Loads Intel MPI from Intel oneAPI if installed under ${INTEL_ONEAPI_ROOT}."
}

module-whatis "Intel MPI from oneAPI"

set oneapi_root ${INTEL_ONEAPI_ROOT}
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

  log_ok "Intel MPI modulefile created: ${MODULEFILES_PATH}/intel-mpi/oneapi"
}

# ------------------------------------------------------------------------------
# Root SSH Setup and Sync
# ------------------------------------------------------------------------------

slurm_setup_root_ssh_if_master() {
  if [[ "${NODE_ROLE}" != "master" ]]; then
    return 0
  fi

  log_section "Checking Root SSH from Master to Compute"

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh

  if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
    log_ok "Root SSH key generated."
  fi

  if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"${COMPUTE_HOST}" "hostname -s" >/dev/null 2>&1; then
    log_ok "Passwordless root SSH to ${COMPUTE_HOST} works."
    return 0
  fi

  log_warn "Passwordless root SSH to ${COMPUTE_HOST} is not working."

  if slurm_confirm "Setup root SSH key copy to ${COMPUTE_HOST} now? [y/N]: "; then
    ssh-copy-id -o StrictHostKeyChecking=no root@"${COMPUTE_HOST}" || {
      log_warn "root ssh-copy-id failed."
      log_warn "Manual command:"
      log_warn "  sudo ssh-copy-id root@${COMPUTE_HOST}"
    }
  fi
}

slurm_sync_to_compute_if_master() {
  if [[ "${NODE_ROLE}" != "master" ]]; then
    return 0
  fi

  log_section "Syncing Slurm and Munge Configs to Compute Node"

  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"${COMPUTE_HOST}" "hostname -s" >/dev/null 2>&1; then
    log_warn "Skipping automatic sync because root SSH is not ready."
    log_warn "Manual sync required:"
    log_warn "  scp /etc/munge/munge.key root@${COMPUTE_HOST}:/etc/munge/munge.key"
    log_warn "  rsync -av /etc/slurm/ root@${COMPUTE_HOST}:/etc/slurm/"
    return 0
  fi

  ssh root@"${COMPUTE_HOST}" "mkdir -p /etc/munge /etc/slurm /var/log/slurm /var/spool/slurmd ${SHARED_SCRATCH_PATH} ${MODULEFILES_PATH}"

  scp /etc/munge/munge.key root@"${COMPUTE_HOST}":/etc/munge/munge.key
  rsync -av /etc/slurm/slurm.conf /etc/slurm/cgroup.conf root@"${COMPUTE_HOST}":/etc/slurm/
  rsync -av "${MODULEFILES_PATH}/" root@"${COMPUTE_HOST}":"${MODULEFILES_PATH}/"
  rsync -av /etc/profile.d/capac-modules.sh root@"${COMPUTE_HOST}":/etc/profile.d/capac-modules.sh

  ssh root@"${COMPUTE_HOST}" "
    chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /run/munge 2>/dev/null || true
    chmod 0700 /etc/munge /var/lib/munge /var/log/munge /run/munge 2>/dev/null || true
    chmod 0400 /etc/munge/munge.key
    chown -R ${SLURM_USER}:${SLURM_USER} /etc/slurm /var/log/slurm /var/spool/slurmd 2>/dev/null || true
    chmod 1777 ${SHARED_SCRATCH_PATH}
    systemctl restart munge || true
    systemctl restart slurmd || true
  "

  log_ok "Configs synced to compute node."
}

# ------------------------------------------------------------------------------
# Services
# ------------------------------------------------------------------------------

slurm_enable_services() {
  log_section "Enabling Slurm Services"

  systemctl enable --now munge
  systemctl restart munge

  if [[ "${NODE_ROLE}" == "master" ]]; then
    systemctl enable --now mariadb
    systemctl enable --now slurmdbd
    systemctl restart slurmdbd

    sleep 3

    systemctl enable --now slurmctld
    systemctl restart slurmctld
  fi

  systemctl enable --now slurmd
  systemctl restart slurmd

  log_ok "Slurm services enabled/restarted."
}

# ------------------------------------------------------------------------------
# Accounting Registration
# ------------------------------------------------------------------------------

slurm_register_accounting_if_master() {
  if [[ "${NODE_ROLE}" != "master" ]]; then
    return 0
  fi

  log_section "Registering Slurm Accounting Cluster"

  sleep 3

  if command -v sacctmgr >/dev/null 2>&1; then
    sacctmgr -i add cluster "${CLUSTER_NAME}" || true
    sacctmgr show cluster -P | tee -a "${LOG_FILE}" || true
  else
    log_warn "sacctmgr not available."
  fi
}

# ------------------------------------------------------------------------------
# Test Jobs
# ------------------------------------------------------------------------------

slurm_create_test_jobs_if_master() {
  if [[ "${NODE_ROLE}" != "master" ]]; then
    return 0
  fi

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
echo "CPU layout:"
lscpu | egrep 'CPU\\(s\\)|Thread|Core|Socket|NUMA'
echo "Running simple parallel hostname test:"
srun bash -c 'echo rank=\${SLURM_PROCID} host=\$(hostname)'
EOF

  chmod +x /opt/slurm-tests/*.sbatch

  log_ok "Test jobs created in /opt/slurm-tests"
  log_info "Run after both nodes are configured:"
  log_info "  sbatch /opt/slurm-tests/hostname-test.sbatch"
  log_info "  sbatch /opt/slurm-tests/cpu-test.sbatch"
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

slurm_summary() {
  log_section "Slurm Cluster Summary"

  log_info "Role       : ${NODE_ROLE}"
  log_info "Cluster    : ${CLUSTER_NAME}"
  log_info "Partition  : ${PARTITION_NAME}"
  log_info "Nodes      : ${MASTER_HOST}, ${COMPUTE_HOST}"

  log_info "Munge:"
  systemctl is-active munge | tee -a "${LOG_FILE}" || true
  munge -n | unmunge | head -10 | tee -a "${LOG_FILE}" || true

  log_info "Slurm services:"
  systemctl is-active slurmctld 2>/dev/null | tee -a "${LOG_FILE}" || true
  systemctl is-active slurmdbd 2>/dev/null | tee -a "${LOG_FILE}" || true
  systemctl is-active slurmd 2>/dev/null | tee -a "${LOG_FILE}" || true

  if [[ "${NODE_ROLE}" == "master" ]]; then
    log_info "Slurm controller ping:"
    scontrol ping | tee -a "${LOG_FILE}" || true

    log_info "Slurm nodes:"
    sinfo -Nel | tee -a "${LOG_FILE}" || true

    log_info "Slurm partition:"
    sinfo | tee -a "${LOG_FILE}" || true

    log_info "Accounting:"
    sacctmgr show cluster -P | tee -a "${LOG_FILE}" || true
  fi

  log_info "Environment Modules:"
  if [[ -f /etc/profile.d/modules.sh ]]; then
    # shellcheck source=/dev/null
    source /etc/profile.d/modules.sh
  fi

  command -v module | tee -a "${LOG_FILE}" || true
  log_info "Modulefiles path: ${MODULEFILES_PATH}"
  find "${MODULEFILES_PATH}" -maxdepth 3 -type f | tee -a "${LOG_FILE}" || true

  log_info "Useful validation commands:"
  log_info "  source /etc/profile.d/modules.sh"
  log_info "  module use ${MODULEFILES_PATH}"
  log_info "  module avail"
  log_info "  module load openmpi/rocky8"
  log_info "  scontrol ping"
  log_info "  sinfo -Nel"
  log_info "  sbatch /opt/slurm-tests/hostname-test.sbatch"

  log_ok "Slurm summary completed."
}