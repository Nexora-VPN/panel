#!/usr/bin/env bash
# Nexora Panel installer and updater. Re-run it to update in place.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
set -euo pipefail

PANEL_REPO="nexora-vpn/panel"
NODE_REPO="nexora-vpn/node"
INSTALL_DIR="/opt/nexora-panel"   # binary + config.json
STATE_DIR="/var/opt/nexora"       # database, node binaries, themes, backups
SERVICE="nexora-panel"
UNIT="/etc/systemd/system/${SERVICE}.service"

PANEL_VERSION=""    # empty = the latest release
NODE_VERSION=""     # empty = the latest release
USE_POSTGRES=0
DO_UNINSTALL=0
PG_DB="nexora"
PG_USER="nexora"

die() { echo "error: $*" >&2; exit 1; }
panel_version() { "${INSTALL_DIR}/nexora-panel" version 2>/dev/null | awk '{print $2}'; }
nexora_panel() { "${INSTALL_DIR}/nexora-panel" "$@"; }
say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*" >&2; }

usage() {
  cat >&2 <<EOF
Nexora Panel installer

  install.sh [--postgres] [--version vX.Y.Z] [--node-version vX.Y.Z]
  install.sh --uninstall

  --postgres          install and configure PostgreSQL instead of SQLite
  --version TAG       install a specific panel release instead of the latest
  --node-version TAG  stage a specific node release instead of the latest
  --uninstall         stop and remove the panel (the database is kept)

Re-running the installer on an existing install performs an update.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --postgres) USE_POSTGRES=1; shift ;;
    --version) PANEL_VERSION="${2:-}"; [[ -n "$PANEL_VERSION" ]] || usage; shift 2 ;;
    --node-version) NODE_VERSION="${2:-}"; [[ -n "$NODE_VERSION" ]] || usage; shift 2 ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ $EUID -eq 0 ]] || die "please run as root"
command -v systemctl >/dev/null || die "this installer needs systemd; use the Docker install instead"
command -v curl >/dev/null || die "curl is required"
command -v tar >/dev/null || die "tar is required"

# --- platform -----------------------------------------------------------------

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    armv7l|armv7) echo "linux-armv7" ;;
    armv6l|armv6) echo "linux-armv6" ;;
    i386|i686) echo "linux-386" ;;
    s390x) echo "linux-s390x" ;;
    riscv64) echo "linux-riscv64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}
ARCH="$(detect_arch)"

[[ -n "$PANEL_VERSION" && "$PANEL_VERSION" != v* ]] && PANEL_VERSION="v${PANEL_VERSION}"
[[ -n "$NODE_VERSION" && "$NODE_VERSION" != v* ]] && NODE_VERSION="v${NODE_VERSION}"

# NEXORA_DOWNLOAD_BASE points at a flat mirror instead of GitHub.
asset_url() {
  local repo="$1" version="$2" name="$3"
  if [[ -n "${NEXORA_DOWNLOAD_BASE:-}" ]]; then
    echo "${NEXORA_DOWNLOAD_BASE%/}/${name}"
  elif [[ -n "$version" ]]; then
    echo "https://github.com/${repo}/releases/download/${version}/${name}"
  else
    echo "https://github.com/${repo}/releases/latest/download/${name}"
  fi
}

# --- uninstall ----------------------------------------------------------------

if [[ $DO_UNINSTALL -eq 1 ]]; then
  say "stopping ${SERVICE}"
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "$UNIT" /usr/local/bin/nexora-panel
  systemctl daemon-reload
  rm -rf "$INSTALL_DIR"
  echo
  echo "Nexora is removed. The database and the backups under ${STATE_DIR}"
  echo "were left alone. Delete them yourself once you are sure — and take a copy"
  echo "of ${STATE_DIR}/backups first if this server is going away:"
  echo "  rm -rf ${STATE_DIR}"
  exit 0
fi

# --- postgres -----------------------------------------------------------------

# Everything to stderr: setup_postgres returns the DSN on stdout.
pkg_install() {
  if command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >&2
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >&2
  elif command -v dnf >/dev/null; then
    dnf install -y -q "$@" >&2
  elif command -v yum >/dev/null; then
    yum install -y -q "$@" >&2
  elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm "$@" >&2
  else
    die "no supported package manager found; install PostgreSQL yourself and re-run without --postgres"
  fi
}

# Avoids `tr < /dev/urandom`, whose SIGPIPE trips `set -o pipefail`.
rand_pass() {
  if command -v openssl >/dev/null; then
    openssl rand -hex 16
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# Idempotent: an update must not rotate the password under a working panel.
setup_postgres() {
  if ! command -v psql >/dev/null; then
    say "installing PostgreSQL" >&2
    if command -v apt-get >/dev/null; then
      pkg_install postgresql postgresql-contrib
    else
      pkg_install postgresql-server postgresql || pkg_install postgresql
      # RHEL-family packages ship an uninitialised cluster.
      if [[ -x /usr/bin/postgresql-setup ]] && [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
        /usr/bin/postgresql-setup --initdb >/dev/null 2>&1 || true
      fi
    fi
  fi
  systemctl enable --now postgresql >/dev/null 2>&1 ||
    systemctl enable --now postgresql.service >/dev/null 2>&1 ||
    die "could not start PostgreSQL"

  local pass
  pass="$(rand_pass)"

  say "configuring the ${PG_DB} database" >&2
  su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'\"" | grep -q 1 ||
    su - postgres -c "psql -q -c \"CREATE ROLE ${PG_USER} LOGIN PASSWORD '${pass}'\"" >/dev/null
  su - postgres -c "psql -q -c \"ALTER ROLE ${PG_USER} PASSWORD '${pass}'\"" >/dev/null
  su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${PG_DB}'\"" | grep -q 1 ||
    su - postgres -c "createdb -O ${PG_USER} ${PG_DB}" >/dev/null

  # Some distributions default loopback TCP to peer auth, which no password
  # can satisfy.
  local hba
  hba="$(su - postgres -c 'psql -tAc "SHOW hba_file"' | tr -d '[:space:]')"
  if [[ -f "$hba" ]] && ! grep -qE "^host +${PG_DB} +${PG_USER} +127\.0\.0\.1/32" "$hba"; then
    printf 'host %s %s 127.0.0.1/32 scram-sha-256\n' "$PG_DB" "$PG_USER" >> "$hba"
    systemctl reload postgresql >/dev/null 2>&1 || systemctl restart postgresql >/dev/null 2>&1 || true
  fi

  echo "host=127.0.0.1 port=5432 user=${PG_USER} password=${pass} dbname=${PG_DB} sslmode=disable"
}

# --- listen port --------------------------------------------------------------

# Below the ephemeral range: above it, a restart can find its number held by an
# outbound socket and fail to bind.
ephemeral_low() {
  local low=""
  if [[ -r /proc/sys/net/ipv4/ip_local_port_range ]]; then
    low="$(awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null || true)"
  fi
  if [[ "$low" =~ ^[0-9]+$ ]] && [[ "$low" -gt 1024 ]]; then
    echo "$low"
  else
    echo 32768   # the kernel default
  fi
}

listening_ports() {
  if command -v ss >/dev/null; then
    ss -ltn 2>/dev/null | awk 'NR>1 {print $4}'
  elif command -v netstat >/dev/null; then
    netstat -ltn 2>/dev/null | awk '{print $4}'
  fi
}

# A here-string, not a pipe: `grep -q` stops at the first match, and the SIGPIPE
# that kills the left side reads as failure under pipefail — "free" for a port
# that is anything but.
port_in_use() {
  local port="$1" listeners
  listeners="$(listening_ports || true)"
  if grep -qE "[:.]${port}\$" <<<"$listeners"; then
    return 0
  fi
  if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
    return 0
  fi
  return 1
}

# Two $RANDOMs: one only reaches 32767, half the range.
pick_port() {
  local low=10000 high span port attempt
  high=$(( $(ephemeral_low) - 1 ))
  if [[ $high -le $low ]]; then
    high=32767
  fi
  span=$(( high - low + 1 ))
  for attempt in $(seq 50); do
    port=$(( low + ((RANDOM << 15 | RANDOM) % span) ))
    if ! port_in_use "$port"; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

# --- install ------------------------------------------------------------------

UPDATING=0
[[ -x "${INSTALL_DIR}/nexora-panel" ]] && UPDATING=1

if [[ $UPDATING -eq 1 ]]; then
  say "updating an existing install ($(panel_version || echo unknown))"
  systemctl stop "$SERVICE" 2>/dev/null || true
else
  say "installing Nexora Panel (${ARCH})"
fi

mkdir -p "$INSTALL_DIR" "${STATE_DIR}/bin" "${STATE_DIR}/sub-themes" "${STATE_DIR}/backups"
# Backups hold every credential the panel has.
chmod 0700 "${STATE_DIR}/backups"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "downloading the panel"
curl -fsSL "$(asset_url "$PANEL_REPO" "$PANEL_VERSION" "nexora-panel-${ARCH}.tar.gz")" -o "${TMP}/panel.tar.gz" ||
  die "could not download the panel for ${ARCH}"
tar -C "$TMP" -xzf "${TMP}/panel.tar.gz"

if [[ $UPDATING -eq 1 ]]; then
  cp -f "${INSTALL_DIR}/nexora-panel" "${INSTALL_DIR}/nexora-panel.previous"
fi
install -m 0755 "${TMP}/nexora-panel/nexora-panel" "${INSTALL_DIR}/nexora-panel"

# The panel serves these to node installers from bin/. The tag comes from the
# redirect "latest" answers with: a binary carries no release tag.
resolve_node_version() {
  [[ -n "$NODE_VERSION" ]] && { echo "$NODE_VERSION"; return; }
  [[ -n "${NEXORA_DOWNLOAD_BASE:-}" ]] && return 0   # a mirror has no tag to ask for
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/${NODE_REPO}/releases/latest" 2>/dev/null || true)"
  case "$url" in
    */releases/tag/*) echo "${url##*/}" ;;
  esac
}

say "downloading node binaries"
NODE_TAG="$(resolve_node_version)"
for node_arch in amd64 arm64; do
  if curl -fsSL "$(asset_url "$NODE_REPO" "$NODE_VERSION" "nexora-node-linux-${node_arch}.tar.gz")" -o "${TMP}/node.tar.gz" 2>/dev/null; then
    tar -C "$TMP" -xzf "${TMP}/node.tar.gz"
    install -m 0755 "${TMP}/nexora-node/nexora-node" "${STATE_DIR}/bin/nexora-node-linux-${node_arch}"
    if [[ -n "$NODE_TAG" ]]; then
      printf '%s\n' "$NODE_TAG" > "${STATE_DIR}/bin/nexora-node-linux-${node_arch}.version"
    else
      rm -f "${STATE_DIR}/bin/nexora-node-linux-${node_arch}.version"
    fi
  else
    warn "no node binary published for linux-${node_arch}; nodes on that architecture must be installed manually"
  fi
done

# Never touched on an update: the operator's DSN lives here.
if [[ ! -f "${INSTALL_DIR}/config.json" ]]; then
  if [[ $USE_POSTGRES -eq 1 ]]; then
    DSN="$(setup_postgres)"
    cat > "${INSTALL_DIR}/config.json" <<EOF
{
  "db": {
    "driver": "postgres",
    "dsn": "${DSN}",
    "verbose": false
  }
}
EOF
  else
    cat > "${INSTALL_DIR}/config.json" <<EOF
{
  "db": {
    "driver": "sqlite",
    "dsn": "${STATE_DIR}/nexora.db",
    "verbose": false
  }
}
EOF
  fi
  chmod 0600 "${INSTALL_DIR}/config.json"
elif [[ $USE_POSTGRES -eq 1 ]]; then
  warn "config.json already exists; leaving the database configuration alone"
fi

# One file, so a copy is a complete rollback point; PostgreSQL is not.
if [[ $UPDATING -eq 1 ]] && [[ -f "${STATE_DIR}/nexora.db" ]]; then
  cp -f "${STATE_DIR}/nexora.db" "${STATE_DIR}/nexora.db.bak"
  say "database backed up to ${STATE_DIR}/nexora.db.bak"
fi

rollback() {
  [[ $UPDATING -eq 1 ]] || return 0
  warn "restoring the previous version"
  mv -f "${INSTALL_DIR}/nexora-panel.previous" "${INSTALL_DIR}/nexora-panel"
  systemctl start "$SERVICE" 2>/dev/null || true
}

say "migrating the database"
if ! ( cd "$STATE_DIR" && "${INSTALL_DIR}/nexora-panel" migrate -config "${INSTALL_DIR}/config.json" ); then
  rollback
  die "the database migration failed; nothing was changed"
fi

# Once, on a panel that has never been configured — `config get` failing is what
# says so. Unset means the binary's own [::]:2095, so a failure still comes up.
if [[ $UPDATING -eq 0 ]] && ! nexora_panel config get web_listen_port >/dev/null 2>&1; then
  if LISTEN_PORT="$(pick_port)"; then
    if nexora_panel config set web_listen_port "$LISTEN_PORT" >/dev/null 2>&1; then
      say "the panel will listen on port ${LISTEN_PORT}"
    else
      warn "could not save the chosen port; the panel will use its default"
    fi
  else
    warn "found no free port to give the panel; it will use its default"
  fi
fi

cat > "$UNIT" <<EOF
[Unit]
Description=Nexora Panel
After=network.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${STATE_DIR}
Environment=NEXORA_STATE_DIR=${STATE_DIR}
ExecStart=${INSTALL_DIR}/nexora-panel run -config ${INSTALL_DIR}/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

ln -sf "${INSTALL_DIR}/nexora-panel" /usr/local/bin/nexora-panel 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now "$SERVICE" >/dev/null

for _ in $(seq 30); do
  systemctl is-active --quiet "$SERVICE" && break
  sleep 0.5
done
systemctl is-active --quiet "$SERVICE" || {
  journalctl -u "$SERVICE" -n 30 --no-pager || true
  rollback
  die "the panel did not start (log above)"
}

echo
if [[ $UPDATING -eq 1 ]]; then
  say "Nexora updated to $(panel_version)"
  echo "  Nothing else to do — your settings, database and admins are unchanged."
  exit 0
fi

# --- first run ----------------------------------------------------------------

TOKEN="$(nexora_panel setup-token 2>/dev/null || true)"
PORT="$(nexora_panel config get web_listen_port 2>/dev/null || echo 2095)"
[[ -n "$PORT" ]] || PORT=2095

# Only the operator knows which address reaches this server, so every candidate
# is printed. Several lookup services: any one can be blocked or down.
public_ip() {
  local url ip
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip="$(curl -fsS --max-time 5 "$url" 2>/dev/null || true)"
    ip="${ip//[[:space:]]/}"
    # A blocked request often answers with an HTML error page, not a failure.
    if [[ "$ip" =~ ^[0-9a-fA-F:.]+$ ]] && [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

local_ips() {
  if command -v ip >/dev/null; then
    ip -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' || true
  else
    hostname -I 2>/dev/null | tr ' ' '\n' || true
  fi
}

setup_link() {
  local addr="$1"
  if [[ "$addr" == *:* ]]; then
    addr="[${addr}]"
  fi
  echo "http://${addr}:${PORT}/setup?t=${TOKEN}"
}

say "Nexora $(panel_version) is installed"
echo
if [[ -n "$TOKEN" ]]; then
  echo "  Finish the setup by opening one of these links — whichever address"
  echo "  reaches this server from where you are:"
  echo
  PUBLIC=""
  if PUBLIC="$(public_ip)"; then
    printf '    %-52s %s\n' "$(setup_link "$PUBLIC")" "(as the internet sees this host)"
  fi
  while read -r addr; do
    if [[ -z "$addr" || "$addr" == "$PUBLIC" ]]; then
      continue
    fi
    printf '    %s\n' "$(setup_link "$addr")"
  done < <(local_ips)
  echo
  if [[ -n "${LISTEN_PORT:-}" && "${LISTEN_PORT:-}" == "$PORT" ]]; then
    echo "  Port ${PORT} was picked at random and is free on this host — open it in"
    echo "  the firewall if one is running. The wizard can move it before you finish."
    echo
  fi
  echo "  Until setup is finished the panel answers nothing else, and nothing at"
  echo "  all without that token — so keep the link private. To print it again:"
  echo
  echo "    nexora-panel setup-token"
else
  echo "  This panel is already set up. Sign in on port ${PORT}."
  echo "  Locked out? Stop the service, then: nexora-panel admin reset-password"
fi
echo
echo "  Service:  systemctl status ${SERVICE}"
echo "  Logs:     journalctl -u ${SERVICE} -f"
echo "  Backups:  ${STATE_DIR}/backups  (turn the schedule on under Settings → Backup)"
echo
