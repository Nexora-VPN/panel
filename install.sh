#!/usr/bin/env bash
# Nexora Panel installer and updater.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
#
# It asks nothing. The only choice it makes is the database — SQLite by default,
# PostgreSQL with --postgres — and that choice is the one thing that cannot be
# made later from the panel, because the panel needs a database to have settings
# at all. Everything else (the main admin, the port, the secret paths, HTTPS) is
# chosen in the setup wizard the panel opens on its first start.
#
# Run it again on a server that already has Nexora and it updates in place,
# keeping the database and config.json untouched.
set -euo pipefail

# Panel and node are released independently, so each has its own repository and
# its own "latest". The panel installer needs both: it installs the panel, and it
# stages node binaries for the node installers the panel serves.
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
# `nexora-panel version` prints "nexora-panel X.Y.Z"; only the number is wanted.
panel_version() { "${INSTALL_DIR}/nexora-panel" version 2>/dev/null | awk '{print $2}'; }
# The binary finds /opt/nexora-panel/config.json on its own; this is just the
# installed path, for use before the PATH symlink is in place.
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

# A release tag is vX.Y.Z; accept it written either way.
[[ -n "$PANEL_VERSION" && "$PANEL_VERSION" != v* ]] && PANEL_VERSION="v${PANEL_VERSION}"
[[ -n "$NODE_VERSION" && "$NODE_VERSION" != v* ]] && NODE_VERSION="v${NODE_VERSION}"

# asset_url composes a release download URL for one repository. Without an
# explicit version this is the "latest" alias, which GitHub resolves only to a
# full release — never to a prerelease. NEXORA_DOWNLOAD_BASE points the installer
# at a single mirror holding both products' assets instead, for hosts that cannot
# reach GitHub; asset names are unique across the two repositories, so one flat
# directory is enough.
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

# pkg_install writes everything to stderr: setup_postgres returns the DSN on
# stdout, and a chatty package manager would end up inside it.
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

# rand_pass returns a 32-character hex secret. It avoids `tr < /dev/urandom`,
# whose SIGPIPE trips `set -o pipefail`.
rand_pass() {
  if command -v openssl >/dev/null; then
    openssl rand -hex 16
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# setup_postgres installs the server, creates the role and database, and returns
# the DSN on stdout. Everything it does is idempotent: an update re-runs it and
# finds the role already there, so the stored password is reused rather than
# rotated out from under a working panel.
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

  # Only ever reached on a fresh install (config.json is what records the DSN,
  # and it is never rewritten), so these are new credentials by definition.
  local pass
  pass="$(rand_pass)"

  say "configuring the ${PG_DB} database" >&2
  su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'\"" | grep -q 1 ||
    su - postgres -c "psql -q -c \"CREATE ROLE ${PG_USER} LOGIN PASSWORD '${pass}'\"" >/dev/null
  su - postgres -c "psql -q -c \"ALTER ROLE ${PG_USER} PASSWORD '${pass}'\"" >/dev/null
  su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${PG_DB}'\"" | grep -q 1 ||
    su - postgres -c "createdb -O ${PG_USER} ${PG_DB}" >/dev/null

  # The panel connects over loopback TCP with a password. Some distributions
  # default that to ident/peer authentication, which no password can satisfy, so
  # make the one rule the panel needs explicit.
  local hba
  hba="$(su - postgres -c 'psql -tAc "SHOW hba_file"' | tr -d '[:space:]')"
  if [[ -f "$hba" ]] && ! grep -qE "^host +${PG_DB} +${PG_USER} +127\.0\.0\.1/32" "$hba"; then
    printf 'host %s %s 127.0.0.1/32 scram-sha-256\n' "$PG_DB" "$PG_USER" >> "$hba"
    systemctl reload postgresql >/dev/null 2>&1 || systemctl restart postgresql >/dev/null 2>&1 || true
  fi

  echo "host=127.0.0.1 port=5432 user=${PG_USER} password=${pass} dbname=${PG_DB} sslmode=disable"
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
# A backup archive holds every credential the panel has — admin password hashes,
# user UUIDs, certificate private keys, the mTLS client key. The panel creates
# this directory 0700 on its own; it is created here too so that an operator who
# looks before taking the first backup finds it, and finds it closed.
chmod 0700 "${STATE_DIR}/backups"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "downloading the panel"
curl -fsSL "$(asset_url "$PANEL_REPO" "$PANEL_VERSION" "nexora-panel-${ARCH}.tar.gz")" -o "${TMP}/panel.tar.gz" ||
  die "could not download the panel for ${ARCH}"
tar -C "$TMP" -xzf "${TMP}/panel.tar.gz"

# The running binary is kept until the new one is in place and migrated, so a
# failed update can be rolled back by hand.
if [[ $UPDATING -eq 1 ]]; then
  cp -f "${INSTALL_DIR}/nexora-panel" "${INSTALL_DIR}/nexora-panel.previous"
fi
install -m 0755 "${TMP}/nexora-panel/nexora-panel" "${INSTALL_DIR}/nexora-panel"

# Node binaries are served to node installers straight from the panel
# (bin/nexora-node-linux-<arch> under its working directory), so adding the first
# node works without the operator staging anything. A missing arch is not fatal:
# the panel simply cannot offer that one.
# resolve_node_version turns an empty NODE_VERSION into the tag GitHub's
# "latest" alias points at, by following the redirect it answers with. The panel
# cannot read a release tag out of a binary, so what is staged has to be recorded
# here or its version is lost — and the panel's automatic node installer shows
# the operator which version it is about to install.
resolve_node_version() {
  [[ -n "$NODE_VERSION" ]] && { echo "$NODE_VERSION"; return; }
  [[ -n "${NEXORA_DOWNLOAD_BASE:-}" ]] && return 0   # a mirror has no tag to ask for
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/${NODE_REPO}/releases/latest" 2>/dev/null || true)"
  # .../releases/tag/vX.Y.Z — anything else and we simply do not know.
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
    # The sidecar is the panel's only way to name the version it serves. A stale
    # one would be worse than none, so it is removed when the tag is unknown.
    if [[ -n "$NODE_TAG" ]]; then
      printf '%s\n' "$NODE_TAG" > "${STATE_DIR}/bin/nexora-node-linux-${node_arch}.version"
    else
      rm -f "${STATE_DIR}/bin/nexora-node-linux-${node_arch}.version"
    fi
  else
    warn "no node binary published for linux-${node_arch}; nodes on that architecture must be installed manually"
  fi
done

# config.json holds the database connection and nothing else. On an update it is
# never touched: it is where the operator's DSN lives.
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

# A SQLite database is one file, so a copy before the migration is a complete,
# cheap rollback point. PostgreSQL is the operator's to dump.
if [[ $UPDATING -eq 1 ]] && [[ -f "${STATE_DIR}/nexora.db" ]]; then
  cp -f "${STATE_DIR}/nexora.db" "${STATE_DIR}/nexora.db.bak"
  say "database backed up to ${STATE_DIR}/nexora.db.bak"
fi

# A failed migration on an update leaves the service down with a binary that
# cannot read the database, so put the old one back and say so plainly rather
# than leaving the operator with a panel that will not start.
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

# On PATH, so the rescue commands in the documentation can be typed verbatim.
# The binary finds /opt/nexora-panel/config.json on its own, so they need no
# flags either.
ln -sf "${INSTALL_DIR}/nexora-panel" /usr/local/bin/nexora-panel 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now "$SERVICE" >/dev/null

# Wait for the unit to actually come up rather than declaring success on the
# strength of `systemctl start` returning.
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

# The setup token authorises creating the main admin, and the panel answers
# nothing at all without it, so it is printed once, here.
TOKEN="$(nexora_panel setup-token 2>/dev/null || true)"
PORT="$(nexora_panel config get web_listen_port 2>/dev/null || echo 2095)"
[[ -n "$PORT" ]] || PORT=2095

# Which address reaches this server is something only the operator knows: a VPS
# has its public address on an interface, but a host behind NAT or inside a
# container sees addressing no client will ever use. So print a link for every
# address found locally *and* one for the address the internet sees this host
# as, and let the operator pick the one that works.
# public_ip asks the internet what address it sees this host as. Several
# services, because any one of them can be blocked or down.
public_ip() {
  local url ip
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip="$(curl -fsS --max-time 5 "$url" 2>/dev/null || true)"
    ip="${ip//[[:space:]]/}"
    # Only accept something shaped like an address: a blocked request often
    # answers with an HTML error page instead of failing outright.
    if [[ "$ip" =~ ^[0-9a-fA-F:.]+$ ]] && [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

# local_ips lists this machine's own global addresses.
local_ips() {
  if command -v ip >/dev/null; then
    ip -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' || true
  else
    hostname -I 2>/dev/null | tr ' ' '\n' || true
  fi
}

# setup_link prints the wizard URL for one address, bracketing IPv6 so the line
# can be copied as it stands.
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
  echo "  Until setup is finished the panel answers nothing else, and nothing at"
  echo "  all without that token — so keep the link private. To print it again:"
  echo
  echo "    nexora-panel setup-token"
else
  echo "  This panel is already set up. Sign in on port ${PORT}."
fi
echo
echo "  Service:  systemctl status ${SERVICE}"
echo "  Logs:     journalctl -u ${SERVICE} -f"
echo "  Backups:  ${STATE_DIR}/backups  (turn the schedule on under Settings → Backup)"
echo
