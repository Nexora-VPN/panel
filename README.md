<div align="center">
  <img src="https://avatars.githubusercontent.com/u/304456640?s=200&v=4" width="96" alt="Nexora">
  <h1>Nexora Panel</h1>
  <p><strong>The control plane.</strong> Releases, install script, Docker stacks and documentation.</p>
</div>

---

Nexora is a proxy management platform made of a **panel** (this repository) and
any number of **nodes** ([`nexora-vpn/node`](https://github.com/nexora-vpn/node)).
The panel is the single source of truth — users, protocols, templates, nodes,
subscriptions — and drives every node over mutual TLS. Nodes hold no database.

This repository publishes the panel: its release binaries, container images,
installer and documentation. The source is not public.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
```

That is the whole install. It asks nothing: the script sets up the database and
the service, then prints a one-time link that opens the setup wizard, where the
main admin account, the panel's port and paths, and HTTPS are chosen.

Until that wizard is finished the panel answers nothing else — every other path
returns 404, and so does the wizard itself without the token in that link — so an
unconfigured panel sitting on a public IP gives a scanner nothing to work with.

| Flag | Effect |
| --- | --- |
| `--postgres` | install and configure PostgreSQL instead of SQLite |
| `--version vX.Y.Z` | install a specific panel release instead of the latest |
| `--node-version vX.Y.Z` | stage a specific node release instead of the latest |
| `--uninstall` | stop and remove the panel (the database is kept) |

Running the script again on a server that already has Nexora **updates** it in
place, keeping the database, `config.json`, settings and admins.

Alongside the panel the installer stages node binaries under
`/var/opt/nexora/bin/`. Those are what the panel hands to node installers, so
adding your first node needs nothing staged by hand.

## Docker

```bash
git clone https://github.com/nexora-vpn/panel
cd panel/docker/sqlite      # or: cd panel/docker/postgres
docker compose up -d
docker compose logs panel | grep setup
```

Images: `ghcr.io/nexora-vpn/panel` (`linux/amd64`, `linux/arm64`), published with
every tagged release.

A third stack, `docker/panel-and-node`, runs a node beside the panel on one
server. It works, and it is **not recommended** — a node's address goes into
every subscription link, so it publishes the panel's address to every user, and
a node under load takes the panel down with it. The
[install guide](docs/en/install.md#panel-and-node-on-the-same-server) has the
two-step start and the caveats.

## Getting around it

**Ctrl-K** (Cmd-K on a Mac) opens one box that searches every page, every
"new …" form and your users — by name, by group and by **subscription id**,
which is what turns "a customer sent me this link and nothing else" into one
paste. Escape puts you back where you were.

The panel also **installs as an app**: Chrome, Edge and Android offer it from
the address bar, iOS through Share → Add to Home Screen, and it works the same
at a base path as at the root. Installing needs HTTPS. There is no offline
mode and there deliberately never will be — every page here is a live read of
a fleet that changes while you are looking at it.

## Updating

The panel updates itself. It checks once a day whether a newer release exists
and shows a banner when there is one; **Settings → Panel update** takes a
backup, downloads the release, checks it against the checksum published with
it, runs it once to be sure it starts on this machine, swaps it in and
restarts — you stay logged in. If the new build does not come up, the previous
binary is put back automatically within about ten seconds. The database is not
rolled back, because migrations only go forward: the backup taken as the first
step is the way back from one.

A Docker install cannot replace its own image and the page says so; it updates
with `docker compose pull && docker compose up -d`. Any install also updates by
running the installer again, which is what to do where the panel cannot update
itself. The daily check is one outbound request and can be switched off
(`nexora-panel config set update_check false`) without disabling the button.

## IPv6

The panel binds the IPv6 wildcard `[::]` by default — on a port the installer
picks at random, or 2095 under Docker — which serves IPv4 as well, so a v4-only,
v6-only or dual-stack server all work with no configuration (on a host with IPv6
switched off the panel falls back to `0.0.0.0` by itself). A node with only an
IPv6 address is added with its address written plainly, `2001:db8::1`, and the
panel brackets it wherever a link, a subscription URL or a client profile needs
it.

## Backups

The panel backs up its own database — **Settings → Backup** in the sidebar.

An archive is a logical dump of every table, not a copy of the database file, so
one taken on SQLite restores onto PostgreSQL and back: it is also how you move
between the two, and how you move a panel to another server. It carries
**everything the panel knows**, credentials included, which is why every backup
route is limited to the main admin and why an archive is worth encrypting before
it leaves the server.

| | |
| --- | --- |
| Download one | Straight to your browser, nothing kept on the server |
| Take one on the host | Written into the backup directory below |
| Schedule | Off by default; an interval in hours and how many archives to keep |
| Encryption | Optional passphrase (scrypt + AES-GCM). The panel cannot recover a lost one |
| Restore | From an upload or from an archive already on the host; the panel restarts into it |

Archives live in `/var/opt/nexora/backups` on a native install, and in
`./backups` next to the `docker-compose.yml` of whichever Docker stack you run.
Copy that directory off the server — a backup that only exists on the machine it
protects is not a backup.

Before replacing anything, a restore writes a **pre-restore snapshot** of the
current database into the same directory. Retention never deletes those; they are
the undo.

**Moving to a new server:** install the panel there and, on the setup wizard's
first screen, choose *Restore a backup* instead of filling the form. The wizard
is the only place a restore is possible before an account exists, which is
exactly the state a fresh install is in. Take the licence key across too — it is
bound to the host's fingerprint, so the new server needs its own.

The schedule is also settable from the command line, which is what a headless or
scripted install wants:

```bash
nexora-panel config set backup_enabled true
nexora-panel config set backup_interval_hours 24
nexora-panel config set backup_keep 14
nexora-panel config set backup_passphrase "a long passphrase"   # optional
```

## Accounts and access

**Roles** decide what each operator can do. Three ship with the panel — main
admin, operator, reseller — and a custom role starts from one of them and takes
permissions away. It can never add any: the panel refuses to store a role
granting a permission you do not hold yourself. A role can also carry limits
that are not permissions — how many users an account on it may own, the largest
device limit it may hand out, the longest plan it may sell.

Two different questions decide what an account reaches: **permissions decide
which pages**, and **ownership decides which users** — a reseller sees the
accounts it owns whatever its permissions say. One account **owns** the panel:
it cannot be deleted or demoted, and only it can hand the panel to another main
admin. See [operators and roles](docs/en/install.md#operators-and-roles).

Operator accounts are the panel's, not the browser's. Sessions are stored, so a
restart or an update logs nobody out, and each operator can see their own open
sessions — address, client, last activity — and end any one of them from the
account menu in the top bar. **Two-factor authentication**, enrolled from that
same menu, is TOTP from any authenticator app, with ten single-use recovery
codes; the sensitive routes — admin management, tokens, the licence, restores,
panel settings — ask for the code again once it is more than ten minutes old.

Failed logins are rate-limited per address and then **banned**, and the ban is
stored, so it survives a restart and lengthens with each repetition. Two
settings decide who that address is: `trusted_proxies` (behind nginx or a CDN,
without it every visitor looks like one address, and the first lockout locks out
everyone) and `login_allowlist`, addresses that are never locked out — your own
network, as the way back in. Both are in **Settings → Security**, alongside the
ban list itself.

## Events

The panel raises an event for everything worth being told about — a user
created or out of quota, a node down or back, a disk over its threshold, a
backup that failed, a licence about to expire, an operator logging in from a new
address — and delivers it to **subscribers you add in Settings → Webhooks**.
Each subscriber has its own URL, its own signing secret and its own list of
events, and delivery is an outbox: a receiver that was down for an hour gets
everything afterwards, signed, with retries and a delivery log you can replay
from. `GET /api/events` lists every event with its payload shape. Telegram,
email and the rest are integrations that sit on top of this, not panel
features.

## Links and subscriptions

A user's subscription carries one entry per way they can reach your fleet, and
two things widen that list. A node may advertise **several link addresses** — a
second IP, a domain, an IPv6 address — each adding a copy of that node's
entries. An inbound may sit behind one or more **domain fronts**: a CDN hostname
clients dial instead of the node, which the CDN forwards to your server by the
name it was given. The two **add, they never multiply** — a front hangs off the
inbound, so it is written once however many nodes serve it — and a front address
written `*.cdn.example.com` gives every customer their own hostname under one
wildcard DNS record, so a blocked name costs one customer rather than all of
them.

Entry names come from a template (`{USER} · {ROUTE} · {REMAINING}`) with a
server-rendered preview, and the response carries the headers clients actually
read — title, quota, update interval, announcement, support link.

See [links and subscriptions](docs/en/subscriptions.md) for all of it, including
what a CDN cannot carry (REALITY, QUIC, port hopping) and why the panel refuses
those pairs when you save them rather than dropping them silently later.

## Documentation

| | Install | Choosing a database | Links and subscriptions | Monitoring |
| --- | --- | --- | --- | --- |
| English | [install](docs/en/install.md) | [database](docs/en/database.md) | [subscriptions](docs/en/subscriptions.md) | [monitoring](docs/en/monitoring.md) |
| فارسی | [نصب](docs/fa/install.md) | [دیتابیس](docs/fa/database.md) | [اشتراک‌ها](docs/fa/subscriptions.md) | [پایش](docs/fa/monitoring.md) |
| Русский | [установка](docs/ru/install.md) | [база данных](docs/ru/database.md) | [подписки](docs/ru/subscriptions.md) | [мониторинг](docs/ru/monitoring.md) |
| 中文 | [安装](docs/zh/install.md) | [数据库](docs/zh/database.md) | [订阅](docs/zh/subscriptions.md) | [监控](docs/zh/monitoring.md) |

## Releases

`nexora-panel-linux-{amd64,arm64,armv5,armv6,armv7,386,s390x,riscv64}.tar.gz`,
each with its `.sha256` beside it — the checksum the panel's own update checks a
download against. Every archive holds the `nexora-panel` binary and the systemd
unit.

Linux only, and the nodes too: the panel is a service under systemd and a node
wraps a Linux data plane, so there is nothing a Windows build would slot into.

The panel and the node are versioned independently — a panel `v1.4.0` does not
imply a node `v1.4.0`. Any node release is driven by any panel release of the
same or newer minor version.

## Recovering access

Every setting that can make the panel unreachable is writable offline, so a
wrong port, domain or path is never a dead end:

```bash
nexora-panel config set web_listen_port 2095
nexora-panel config set web_listen_ip ""
nexora-panel config set web_domain ""
nexora-panel config set web_basepath ""
systemctl restart nexora-panel
```

A forgotten password and a lost database are not dead ends either. These work
with the panel stopped, which is the state they are for:

```bash
nexora-panel admin list                # the accounts, and which one is the main admin
nexora-panel admin reset-password      # asks for the new one; never echoes it
nexora-panel restore /var/opt/nexora/backups/nexora-backup-20260914-030000.tar.gz
```

`reset-password` is also the way back from a lost phone: it turns two-factor
authentication off for that account and ends every session it has open, so one
command covers both halves of the same emergency. `restore` prints what the
archive holds before it asks to replace anything, and keeps this install's own
address settings and licence. The command line goes no further than this: managing users, nodes or plans is the panel's job, and every
one of these commands exists only for the moment the panel cannot be reached.

See `nexora-panel help` for the full command list.

## Support

- **Bugs and feature requests** — [open an issue here](https://github.com/nexora-vpn/panel/issues).
  Node issues belong in [`nexora-vpn/node`](https://github.com/nexora-vpn/node/issues).
- **Security vulnerabilities** — report them privately through
  [the organisation's security advisories](https://github.com/nexora-vpn/.github/security/advisories/new).
  Please do not open a public issue for those.

## Licence

Nexora Panel is proprietary software, licensed per installation — see
[LICENSE](LICENSE). Without a key it runs on a **free tier** (10 inbounds, 10
outbounds, 10 endpoints, 10 users, 10 nodes) with the full feature set, so everything
can be evaluated before buying. A key is bound to the panel host's hardware
fingerprint, which `nexora-panel hwid` prints.
