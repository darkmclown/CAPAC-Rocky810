#!/usr/bin/env bash
# ansys-rocky810-install-everything.sh
# Purpose: Install the complete union of ANSYS Linux prerequisite libraries on Rocky Linux 8.10.
# Source: Extracted from ANSYS Installation and Licensing Documentation PDF uploaded in this chat.
# Usage:
#   chmod +x ansys-rocky810-install-everything.sh
#   sudo ./ansys-rocky810-install-everything.sh
#
# Optional:
#   sudo ./ansys-rocky810-install-everything.sh --with-devtools --with-hpc --dry-run
#   sudo ./ansys-rocky810-install-everything.sh --skip-repos
#
# Notes:
# - This installs the full union of packages across ANSYS products/components found in the document.
# - Some packages may require EPEL, PowerTools/CRB, AppStream, or vendor repos depending on your Rocky mirror.
# - Some vendor-specific packages may not exist in every Rocky 8.10 repo. The script reports any missing packages.
# - rocm-runtime is an AMD ROCm package and is not in standard Rocky/EPEL repos; it is treated as optional.

set -Eeuo pipefail

LOG_FILE="${LOG_FILE:-/var/log/ansys-rocky810-install-everything.log}"
REPORT_FILE="${REPORT_FILE:-/var/log/ansys-rocky810-install-everything-report.txt}"
DRY_RUN=0
SKIP_REPOS=0
WITH_DEVTOOLS=0
WITH_HPC=0
STRICT=0

usage() {
  cat <<'USAGE'
ANSYS Rocky Linux 8.10 - install everything prerequisite script

Usage:
  sudo ./ansys-rocky810-install-everything.sh [options]

Options:
  --with-devtools   Install common build/compiler tools in addition to ANSYS library prerequisites.
  --with-hpc        Install common HPC/RDMA/MPI helper packages in addition to prerequisite libraries.
  --skip-repos      Do not enable EPEL / PowerTools / AppStream repositories.
  --strict          Fail if any mandatory package cannot be installed. Optional/vendor packages only warn.
  --dry-run         Print actions and package list only; do not install.
  -h, --help        Show help.

Examples:
  sudo ./ansys-rocky810-install-everything.sh
  sudo ./ansys-rocky810-install-everything.sh --with-devtools --with-hpc
  sudo ./ansys-rocky810-install-everything.sh --dry-run
USAGE
}

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_cmd() {
  log "+ $*"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-devtools) WITH_DEVTOOLS=1; shift ;;
    --with-hpc) WITH_HPC=1; shift ;;
    --skip-repos) SKIP_REPOS=1; shift ;;
    --strict) STRICT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || fail "Run as root, for example: sudo $0"
[[ -r /etc/os-release ]] || fail "/etc/os-release not found."
. /etc/os-release

log "Starting ANSYS full prerequisite installation."
log "Detected OS: ${PRETTY_NAME:-unknown}"

if [[ "${ID:-}" != "rocky" || "${VERSION_ID:-}" != 8* ]]; then
  log "WARNING: This script is optimized for Rocky Linux 8.10. Detected ${PRETTY_NAME:-unknown}. Continuing."
fi

if ! command -v dnf >/dev/null 2>&1; then
  fail "dnf package manager not found. This script expects Rocky/RHEL 8 family."
fi

# Full union of ANSYS prerequisite packages extracted for Rocky/RHEL 8 rows.
ANSYS_PACKAGES=(
  brotli
  bzip2-libs
  cyrus-sasl-lib
  expat
  fontconfig
  freetype
  glib2
  glibc
  glibc-devel
  gmp
  gnutls
  gzip
  keyutils-libs
  krb5-libs
  libICE
  libSM
  libX11
  libX11-xcb
  libXau
  libcom_err
  libcurl
  libffi
  libidn2
  libjpeg-turbo
  libnghttp2
  libnsl
  libnsl2
  libpng
  libpsl
  libselinux
  libssh
  libtasn1
  libunistring
  libuuid
  libxcb
  libxcrypt
  libxkbcommon
  libxkbcommon-x11
  libzstd
  nettle
  openldap
  openssl-libs
  p11-kit
  pcre
  pcre2
  tar
  which
  xcb-util
  xcb-util-cursor
  xcb-util-image
  xcb-util-keysyms
  xcb-util-renderutil
  xcb-util-wm
  xorg-x11-fonts-100dpi
  xorg-x11-fonts-75dpi
  zlib
  alsa-lib
  at-spi2-atk
  at-spi2-core
  atk
  audit-libs
  avahi-libs
  cairo
  cairo-gobject
  cups-libs
  dbus-libs
  fribidi
  gdk-pixbuf2
  graphite2
  gtk3
  harfbuzz
  libXcomposite
  libXcursor
  libXdamage
  libXext
  libXfixes
  libXi
  libXinerama
  libXmu
  libXrandr
  libXrender
  libXt
  libXtst
  libXxf86vm
  libblkid
  libcap
  libcap-ng
  libdatrie
  libdrm
  libepoxy
  libgcc
  libgcrypt
  libglvnd
  libglvnd-egl
  libglvnd-glx
  libglvnd-opengl
  libgpg-error
  libmount
  libreoffice-ure
  libthai
  libwayland-client
  libwayland-cursor
  libwayland-egl
  libwayland-server
  libxkbfile
  libxml2
  lz4-libs
  mesa-libgbm
  nspr
  nss
  nss-softokn
  nss-util
  ocl-icd
  octave
  pango
  pixman
  systemd-libs
  xz-libs
  aspell
  elfutils-libelf
  enchant2
  gstreamer1
  gstreamer1-plugins-base
  harfbuzz-icu
  hyphen
  infiniband-diags
  libXft
  libatomic
  libglvnd-gles
  libibumad
  libibverbs
  libicu
  libnl3
  libnotify
  libpciaccess
  libpng12
  librdmacm
  libsecret
  libsoup
  libstdc++
  libtirpc
  libwebp
  libxshmfence
  libxslt
  motif
  munge-libs
  nss-softokn-freebl
  numactl-libs
  orc
  perl-devel
  webkit2gtk3
  webkit2gtk3-jsc
  woff2
  libXp
  ncurses-libs
  rocm-runtime
  libXdmcp
  mesa-libglapi
  glibc.i686
  compat-hwloc1
  compat-openssl10
  flac-libs
  gsm
  jbigkit-devel
  jbigkit-libs
  libasyncns
  libdeflate
  libfontenc
  libogg
  libsndfile
  libvorbis
  ocl-icd-devel
  pam
  pulseaudio-libs
  pulseaudio-libs-glib2
  make
  pcsc-lite-libs
  libX11.i686
  libXau.i686
  libxcb.i686
  libtheora
  libtiff
  openjpeg2
  pcre2-utf32
  freeglut
  libtool-ltdl
  pciutils-libs
  openssl3-libs
  libtirpc-devel
  xterm
  graphviz
  libgomp
  ucx
)

DEVTOOLS_PACKAGES=(
  gcc
  gcc-c++
  gcc-gfortran
  make
  cmake
  automake
  autoconf
  libtool
  patch
  patchutils
  git
  wget
  curl
  unzip
  bzip2
  xz
  tar
  python3
  python3-pip
  redhat-lsb-core
  strace
  lsof
  net-tools
  bind-utils
  pciutils
  psmisc
)

HPC_PACKAGES=(
  numactl
  numactl-libs
  hwloc
  environment-modules
  rdma-core
  rdma-core-devel
  libibverbs
  libibverbs-utils
  librdmacm
  librdmacm-utils
  infiniband-diags
  ucx
  ucx-devel
  openmpi
  openmpi-devel
  mpich
  mpich-devel
  munge
  munge-libs
)

# Packages from vendor-specific repositories or older compatibility repositories.
# They are attempted when available, but absence should not block the full ANSYS prerequisite install.
OPTIONAL_PACKAGES=(
  rocm-runtime
  compat-hwloc1
  compat-openssl10
  libpng12
  libXp
  openssl3-libs
)

is_optional_pkg() {
  local candidate="$1"
  local opt
  for opt in "${OPTIONAL_PACKAGES[@]}"; do
    [[ "$candidate" == "$opt" ]] && return 0
  done
  return 1
}

pkg_available_or_installed() {
  local pkg="$1"
  rpm -q "$pkg" >/dev/null 2>&1 && return 0
  dnf -q repoquery --available "$pkg" >/dev/null 2>&1 && return 0
  return 1
}

unique_packages() {
  awk '!seen[$0]++'
}

write_package_list() {
  local tmp="/tmp/ansys_pkg_list.$$"
  printf '%s\n' "${ANSYS_PACKAGES[@]}" > "$tmp"
  if [[ "$WITH_DEVTOOLS" -eq 1 ]]; then
    printf '%s\n' "${DEVTOOLS_PACKAGES[@]}" >> "$tmp"
  fi
  if [[ "$WITH_HPC" -eq 1 ]]; then
    printf '%s\n' "${HPC_PACKAGES[@]}" >> "$tmp"
  fi
  unique_packages < "$tmp"
  rm -f "$tmp"
}

PKG_FILE="/tmp/ansys-all-packages.$$"
write_package_list > "$PKG_FILE"
PKG_COUNT=$(wc -l < "$PKG_FILE" | tr -d ' ')
log "Total unique packages requested: ${PKG_COUNT}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "Packages that would be installed:"
  cat "$PKG_FILE"
  echo
fi

if [[ "$SKIP_REPOS" -eq 0 ]]; then
  log "Enabling common Rocky 8 repositories: BaseOS/AppStream/PowerTools/EPEL where available."
  run_cmd dnf -y install dnf-plugins-core || true
  run_cmd dnf -y config-manager --set-enabled baseos || true
  run_cmd dnf -y config-manager --set-enabled appstream || true
  run_cmd dnf -y config-manager --set-enabled powertools || true
  run_cmd dnf -y config-manager --set-enabled crb || true
  run_cmd dnf -y install epel-release || true
  run_cmd dnf -y makecache || true
else
  log "Skipping repository enablement because --skip-repos was specified."
fi

log "Resolving available packages before installation."
if [[ "$DRY_RUN" -eq 0 ]]; then
  AVAILABLE_FILE="/tmp/ansys-available-packages.$$"
  MANDATORY_MISSING_FILE="/tmp/ansys-mandatory-missing-packages.$$"
  OPTIONAL_MISSING_FILE="/tmp/ansys-optional-missing-packages.$$"
  INSTALLED_FILE="/tmp/ansys-installed-packages.$$"
  : > "$AVAILABLE_FILE"
  : > "$MANDATORY_MISSING_FILE"
  : > "$OPTIONAL_MISSING_FILE"
  : > "$INSTALLED_FILE"

  while read -r pkg; do
    [[ -n "$pkg" ]] || continue
    if pkg_available_or_installed "$pkg"; then
      echo "$pkg" >> "$AVAILABLE_FILE"
    else
      if is_optional_pkg "$pkg"; then
        echo "$pkg" >> "$OPTIONAL_MISSING_FILE"
        log "Optional/vendor package not available; skipping: $pkg"
      else
        echo "$pkg" >> "$MANDATORY_MISSING_FILE"
        log "Package not available in enabled repos; will report: $pkg"
      fi
    fi
  done < "$PKG_FILE"

  log "Installing available ANSYS prerequisite packages with dnf."
  if [[ -s "$AVAILABLE_FILE" ]]; then
    if dnf -y install --skip-broken $(cat "$AVAILABLE_FILE") 2>&1 | tee -a "$LOG_FILE"; then
      log "dnf install completed for available package set."
    else
      log "Bulk dnf install reported an error. Trying package-by-package fallback."
      while read -r pkg; do
        [[ -n "$pkg" ]] || continue
        rpm -q "$pkg" >/dev/null 2>&1 && continue
        if ! dnf -y install "$pkg" >>"$LOG_FILE" 2>&1; then
          if is_optional_pkg "$pkg"; then
            grep -qxF "$pkg" "$OPTIONAL_MISSING_FILE" || echo "$pkg" >> "$OPTIONAL_MISSING_FILE"
          else
            grep -qxF "$pkg" "$MANDATORY_MISSING_FILE" || echo "$pkg" >> "$MANDATORY_MISSING_FILE"
          fi
        fi
      done < "$AVAILABLE_FILE"
    fi
  fi

  while read -r pkg; do
    [[ -n "$pkg" ]] || continue
    if rpm -q "$pkg" >/dev/null 2>&1; then
      echo "$pkg" >> "$INSTALLED_FILE"
    fi
  done < "$PKG_FILE"

  {
    echo "ANSYS Rocky Linux 8.10 prerequisite installation report"
    echo "Generated: $(date '+%F %T')"
    echo "OS: ${PRETTY_NAME:-unknown}"
    echo
    echo "Requested packages: $(wc -l < "$PKG_FILE" | tr -d ' ')"
    echo "Available packages attempted: $(wc -l < "$AVAILABLE_FILE" | tr -d ' ')"
    echo "Installed/resolved packages: $(wc -l < "$INSTALLED_FILE" | tr -d ' ')"
    echo "Mandatory missing/unavailable packages: $(wc -l < "$MANDATORY_MISSING_FILE" | tr -d ' ')"
    echo "Optional/vendor missing/unavailable packages: $(wc -l < "$OPTIONAL_MISSING_FILE" | tr -d ' ')"
    echo
    echo "Mandatory missing/unavailable package list:"
    if [[ -s "$MANDATORY_MISSING_FILE" ]]; then
      cat "$MANDATORY_MISSING_FILE"
    else
      echo "None"
    fi
    echo
    echo "Optional/vendor missing/unavailable package list:"
    if [[ -s "$OPTIONAL_MISSING_FILE" ]]; then
      cat "$OPTIONAL_MISSING_FILE"
    else
      echo "None"
    fi
    echo
    echo "Installed/resolved package list:"
    cat "$INSTALLED_FILE"
  } > "$REPORT_FILE"

  log "Report written to $REPORT_FILE"

  if [[ -s "$MANDATORY_MISSING_FILE" ]]; then
    log "WARNING: Some mandatory packages were not available from enabled repositories. Review $REPORT_FILE."
    if [[ "$STRICT" -eq 1 ]]; then
      fail "Mandatory missing packages found and --strict was specified."
    fi
  fi

  if [[ -s "$OPTIONAL_MISSING_FILE" ]]; then
    log "Optional/vendor packages were unavailable and skipped. Review $REPORT_FILE."
  fi

  rm -f "$AVAILABLE_FILE" "$MANDATORY_MISSING_FILE" "$OPTIONAL_MISSING_FILE" "$INSTALLED_FILE"
else
  log "Dry run selected; no packages installed."
fi

# Useful post-install checks. These do not fail the script except in strict rpm package mode above.
log "Running basic validation checks."
if [[ "$DRY_RUN" -eq 0 ]]; then
  {
    echo
    echo "Validation checks:"
    echo "glibc: $(rpm -q glibc 2>/dev/null || true)"
    echo "libstdc++: $(rpm -q libstdc++ 2>/dev/null || true)"
    echo "libX11: $(rpm -q libX11 2>/dev/null || true)"
    echo "mesa/libGL: $(rpm -q libglvnd-glx 2>/dev/null || true)"
    echo "OpenCL ICD: $(rpm -q ocl-icd 2>/dev/null || true)"
    echo "UCX: $(rpm -q ucx 2>/dev/null || true)"
    echo "32-bit glibc: $(rpm -q glibc.i686 2>/dev/null || true)"
    echo
    echo "Enabled repositories:"
    dnf repolist enabled || true
  } >> "$REPORT_FILE"
fi

rm -f "$PKG_FILE"
log "Completed. Log: $LOG_FILE"
log "Completed. Report: $REPORT_FILE"
