# Installing Nexora

Nexora is a panel (the control plane) plus any number of nodes (the data plane).
This page installs the panel. Nodes are added later from the panel itself, which
hands you a one-line command for each one.

The installer asks nothing. The only decision it makes for you is the database —
and that is the one thing the panel cannot choose later, because it needs a
database in order to have settings at all. Everything else — the main admin, the
port, the secret paths, HTTPS — is chosen in the setup wizard that opens the
first time you visit the panel.

## Requirements

- A 64-bit Linux server with systemd (Debian 11+, Ubuntu 20.04+, RHEL 9+,
  or similar). 32-bit ARM and x86 are supported too.
- Root access.
- An open TCP port for the panel (2095 by default). The panel binds the IPv6
  wildcard, which serves IPv4 as well, so a v4-only, v6-only or dual-stack
  server all work unchanged.

## Install

With SQLite, which needs no other service:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
```

With PostgreSQL, which the installer installs and configures for you:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh) --postgres
```

To pin a specific release, add `--version v1.2.3`.

The panel and the node are released separately, so they have separate version
numbers. Alongside the panel the installer also stages node binaries, which are
what the panel hands to node installers later; `--node-version v1.2.3` pins
those. Without it you get the latest node release, which is what you want unless
you are reproducing a specific fleet.

SQLite is the right default: a Nexora panel is a small database, and one file is
far easier to back up and move. Choose PostgreSQL when you already run one, or
when your panel serves a large user base — and note that this is the one decision
the panel cannot revisit on its own, though you can migrate later with a backup.
[Choosing a database](database.md) gives the thresholds, what the panel tunes for
you on either backend, and the migration steps.

## Finish the setup

The installer ends by printing a link like:

```
http://203.0.113.10:2095/setup?t=9f3c1ad2…
```

Open it. That token authorises creating the main admin account, so treat it like
a password and do not paste it anywhere public. It stops working the moment
setup completes.

Until setup is finished the panel answers **nothing else**: every other path —
the login page, the API, subscription links — returns 404, and so does the setup
page itself without the token. An unconfigured panel on a public IP therefore
gives a scanner nothing to work with.

The installer prints one link per address it found, plus one for the address
the internet sees this host as. Use whichever actually reaches the server: on a
VPS that is usually the public one, on a container host most of the others are
virtual bridge addressing that reaches nothing.

An IPv6 address appears in those links bracketed, which is what a URL needs —
`http://[2001:db8::10]:2095/setup?t=…`. Paste it whole; a browser will not
accept it without the brackets.

If you lose the links, print the token again on the server and rebuild a URL
around it:

```bash
nexora-panel setup-token
# → 9f3c1ad2…   then open http://YOUR-SERVER:2095/setup?t=9f3c1ad2…
```

The wizard collects everything in one form and saves it in one step:

- **Main administrator** — the account that configures the panel and sees every
  subscription. At least 12 characters, mixing three of lowercase, uppercase,
  digits and symbols.
- **Panel address** — the IP and port to listen on, and a secret path the panel
  answers under. A random path is proposed; keeping it means scanners that find
  your port still do not find a login page.
- **Subscription path** — where subscription links are built. It must differ
  from the panel path.
- **HTTPS** — on by default. The panel issues its own certificate and renews it
  before it expires.
  - **Certificate addresses** are pre-filled with the address you opened the
    wizard at, plus any publicly routable address found on the machine. Edit
    them: the panel cannot know which address your clients will use. Inside a
    container it only sees bridge addressing, and behind NAT the public address
    is on no interface at all — so if the address you type in your browser is
    not listed, add it. IPv6 addresses go in plainly (`2001:db8::10`); brackets
    are accepted and dropped.
  - Add a domain and the certificate is reissued to cover it; a subscription
    domain rides on the same certificate.
  - You may turn HTTPS off, but then passwords and subscription links travel in
    clear text.
- **Time zone** — what every timestamp in the panel is rendered in.

Saving restarts the panel onto the address you just described, and the browser
follows it. With a self-signed certificate your browser warns once — accept it
and continue.

## Disguising the panel

A secret base path already keeps a scanner that finds your port from finding a
login page. What it does not fix is the port itself: every other address answers
404, and a host that completes a TLS handshake and then answers 404 to
everything is not an ordinary server. It is a small signal, and it is the one
that survives having no login page to find.

**Settings → panel → masquerade directory** takes an absolute path, and every
address on that port that is not the panel, a subscription or the rule-set
mirror is served from it as an ordinary web site. `https://panel.example.com/`
becomes whatever you put in that directory; the panel stays at its base path.
It applies after a panel restart.

The panel ships no page of its own, deliberately. A decoy included with the
panel would be byte-for-byte identical on every install, and a scanner would
key on the decoy instead of on the silence — a better fingerprint than the one
it replaced. Put something there that suits the address: a landing page, a
company site, a copy of whatever you would host anyway.

Three things it does not do, each on purpose:

- **It does not touch the API.** A request the panel accepted is the panel's, so
  `GET /panel/api/users` without credentials is still a JSON 401. Turning
  authentication failures into web pages would break every integration and the
  panel's own interface with them.
- **It does not list directories and does not serve dotfiles.** A listing is how
  somebody reads the whole directory at once, and a directory copied off a host
  arrives with a `.git` or a `.env` in it more often than not. A symlink
  pointing out of the directory is not followed.
- **It does nothing without a base path.** With the panel at the root there is
  no address left for the decoy to cover. Set a base path first.

A relative path is refused at save time, and so is `/`. A relative one would
resolve against the panel's own working directory, which is where its database
lives.

## Docker

Two stacks, one per database. Pick a directory and start it:

```bash
git clone https://github.com/nexora-vpn/panel
cd panel/docker/sqlite      # or: cd panel/docker/postgres
docker compose up -d
docker compose logs panel | grep setup
```

For the PostgreSQL stack, copy `.env.example` to `.env` and set a password
before the first start.

Each stack keeps what has to survive the container next to its compose file: the
SQLite database in `./data` (the PostgreSQL stack uses a named volume instead),
node binaries in `./bin`, backup archives in `./backups` — see
[Backups](#backups) — and the mirrored rule-set files the panel serves to its
nodes in `./rulesets`. That last one is a cache: clearing it is safe, and the
panel re-downloads whatever is missing on the next start.

In Docker the panel's port is pinned by `NEXORA_WEB_LISTEN` in the compose file,
because the published port mapping lives there too. Changing the port in the
panel UI would only make the container unreachable, so change both together.

`NEXORA_WEB_LISTEN` binds *inside* the container; what reaches the host is the
`ports:` mapping, and Docker publishes on IPv4 only unless told otherwise. On an
IPv6-only host, enable IPv6 in the daemon (`"ipv6": true` and `"ip6tables": true`
in `/etc/docker/daemon.json`) and publish on both:

```yaml
    ports:
      - "0.0.0.0:2095:2095"
      - "[::]:2095:2095"
```

### Panel and node on the same server

`docker/panel-and-node` is the SQLite stack with a node next to it. It is **not
recommended**: a node's address goes into every subscription link you hand out,
so running one here publishes the panel's address to every user, and client
traffic is unbounded, so a node under load takes the panel — and every other
node's subscriptions — down with it. For a lab, a demo or a small single-server
deployment it is a reasonable trade. The
[node's install guide](https://github.com/nexora-vpn/node/blob/main/docs/en/install.md#panel-and-node-on-the-same-server)
lists the caveats in full.

The node needs the panel's client certificate before it can start, and the panel
only offers that once a node has been added in it — so this stack starts in two
steps:

```bash
cd panel/docker/panel-and-node
docker compose up -d panel
docker compose logs panel | grep setup      # open the link, finish the wizard

# then in the panel: add a node with address 127.0.0.1 and port 62050, and save
# the client certificate from its install page as ./certs/panel_ca.pem
docker compose up -d node
```

Both services use host networking — the node because the ports its inbounds use
are chosen in the panel afterwards, the panel so it can reach the node on
127.0.0.1. That leaves no port mapping to keep in sync, so this is the one stack
that does *not* pin `NEXORA_WEB_LISTEN`: the port chosen in the wizard binds
straight onto the host, as in a native install. The node's control port never
leaves the machine and needs no firewall rule.

## Updating

Run the installer again. It detects the existing install and updates in place:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
```

It stops the service, backs up a SQLite database to `nexora.db.bak`, keeps the
previous binary at `/opt/nexora-panel/nexora-panel.previous`, migrates, and
starts again. Your `config.json`, settings and admin accounts are untouched. If
you use PostgreSQL, take your own dump first.

Docker updates the usual way:

```bash
docker compose pull && docker compose up -d
```

## Locked out?

Every setting that can make the panel unreachable is writable from the command
line, without the panel running:

```bash
nexora-panel config list                       # what is set
nexora-panel config set web_listen_port 2095   # a port you can reach
nexora-panel config set web_listen_ip ""       # bind everywhere again (v4 and v6)
nexora-panel config set web_domain ""          # stop restricting the hostname
nexora-panel config set web_basepath ""        # serve at the root again
nexora-panel config set sub_domain ""          # stop reserving hosts for subscriptions
systemctl restart nexora-panel
```

That last one is the least obvious way to lose the panel, and it only bites when
you have **no base path**. A domain listed in `sub_domain` serves subscriptions
and nothing else, so an end user's link reveals nothing about where the panel is
administered — and with the panel at the root of every host, that leaves nowhere
to reach it on those names. List the only addresses you actually use
(`localhost`, your server's IP) and it is unreachable from everywhere at once.

Set a base path and the trap is gone: the panel stays reachable at that prefix on
every host, subscription domains included. A customer holding a link would have
to guess the prefix, which is already the only thing protecting the panel on your
server's IP.

The installer puts `nexora-panel` on your PATH and the binary finds its own
config file, so these work from any directory. In Docker, prefix them with
`docker compose exec panel /app/`.

**Forgotten password.** The same offline route, for the account instead of the
address:

```bash
nexora-panel admin list                        # which accounts exist, and which is the main one
nexora-panel admin reset-password              # the main admin; the password is typed in, not echoed
nexora-panel admin reset-password -user alice  # any other account
```

With no `-user` it takes the only main admin, and refuses — naming them — if
there is more than one. The new password is asked for twice and never echoed;
`-pass` sets it in one go for an unattended install, at the price of leaving it
in your shell history.

The reset does three things, because a lost password and a lost phone are the
same emergency: it sets the password, **turns two-factor authentication off**
for that account (the seed and its recovery codes are cleared, so the operator
enrols again from the panel), and **ends every session that account has open**.
A running panel keeps a cached session for up to a minute of activity, which the
command says; restart it if that minute matters.

**Locked out by a ban.** Five failed logins from one address lock it out, and
since the ban is stored it survives a restart. Two settings decide who that
address is and who can never be locked out:

```bash
nexora-panel config set trusted_proxies "10.0.0.0/8"   # your nginx / CDN, or empty
nexora-panel config set login_allowlist "203.0.113.7"  # addresses never banned
```

**A panel behind a reverse proxy or a CDN with no `trusted_proxies` sees every
visitor as one address**, so the first lockout locks out everybody. Set it to
the proxy's address, and keep your own network in `login_allowlist` as the way
back in. The main admin can also clear a ban from **Settings → Security** once
back inside.

## IPv6

Nothing here needs configuring for it. The panel listens on `[::]:2095` by
default, which on a dual-stack host answers IPv4 too; a host with IPv6 switched
off cannot bind that and the panel falls back to `0.0.0.0:2095` by itself. To
bind one family only, set `web_listen_ip` to a literal address (`::` or
`0.0.0.0`, or one specific address) in the wizard or from the command line.

Nodes are the same story from the other side: a node with only an IPv6 address is
added with its address written plainly (`2001:db8::1`, brackets optional), and
the panel brackets it wherever the syntax requires — share links come out as
`vless://…@[2001:db8::1]:443?…` and a wireguard profile as
`Endpoint = [2001:db8::1]:51820`, while a clash, sing-box or OpenVPN profile
carries the bare address. Subscription URLs built on an IPv6 panel address are
bracketed for the same reason.

## Your first inbound

**Inbounds → From a preset.** A preset is a protocol with its transport and its
TLS decision already made — VLESS + REALITY, VLESS or Trojan over WebSocket
behind a CDN, gRPC, Hysteria2 — so the first one is a pick and a save rather than
four tabs of choices.

Picking one **creates nothing**. It fills the ordinary inbound form, you confirm
it, and what lands is an ordinary inbound row: nothing afterwards remembers which
preset made it, and every field stays editable. The port, the tag and the
transport path are generated per install, and for REALITY the panel mints the key
pair and the short IDs when you save — there is no key to find and paste.

The shelf itself is a file the panel serves, so you can add to it. Drop a `.json`
into `/var/opt/nexora/presets/` (or whatever **Settings → Preset catalogue**
points at) and it is merged onto the built-in list by key: a new key is added, an
existing one replaced. That is also how you re-point a rule-set entry at a mirror
where the upstream is blocked. A file that does not parse is skipped with a line
in the panel log rather than taking the catalogue with it, and the settings page
names the files actually in effect.

## Routing and DNS presets

**Templates → the template → Routing (or DNS) → From a preset.** The same shelf
idea as inbounds: a routing block made of lists the panel already mirrors — block
ads, and send Iranian (or Chinese, or Russian) domains and addresses out at the
node instead of any further — and a set of encrypted resolvers for the DNS side.

Applying a routing preset **replaces** the template's rules. That is deliberate:
rule order *is* the routing, so merging somebody's rules with a preset's would
produce an order neither of them chose. The rule sets it needs are added to the
selection rather than replacing it.

The part worth knowing about is what happens when a preset needs a list you do
not have. The panel leaves out a rule set it has no copy of **and every rule
matching on it** — it has to, because a node refuses its whole configuration if a
rule names a rule-set nothing defines. So a preset applied without its lists
would be a template that blocks nothing, with nothing anywhere saying why. The
dialog checks first: it names the missing lists and offers to download them
before applying, and it refuses outright when a list is one the catalogue cannot
get either.

The DNS presets are Cloudflare, Google, Quad9 and AdGuard over DNS-over-TLS, plus
the node's own system resolver. AdGuard blocks ads at the resolver, which is an
alternative to the ad-blocking routing preset rather than a companion to it.

## Links and subscriptions

Once the fleet is up, what your customers receive is its own subject:
**[links and subscriptions](subscriptions.md)**. It covers advertising several
addresses per node, putting a CDN in front of an inbound (including the wildcard
DNS record a per-customer hostname needs, and why the panel refuses to front a
REALITY or Hysteria inbound), naming the entries from a template, and the one
client setting — **Mux**, in Xray-based apps — that silently breaks these
configurations.

## Monitoring

The panel publishes its own figures — nodes up, disk and memory per node,
traffic, accounts by status, licence headroom, the event bus — at `/metrics` in
the Prometheus format. **[Monitoring](monitoring.md)** has a compose overlay that
runs Prometheus and Grafana beside your panel with a dashboard already
provisioned, and four alerts worth having. Two things to know before you start:
the endpoint needs an API token (it names every node you run), and a figure a
node did not report has no series at all rather than a zero.

## Backups

The panel backs up its own database, from **Settings → Backup** in the sidebar
(main admin only — an archive holds every credential the panel has).

An archive is a logical dump of every table inside a gzipped tar, not a copy of
the database file. That is why one taken on SQLite restores onto PostgreSQL and
back, and why it is the way to move a panel to another server.

```
Settings → Backup
├─ Download          straight to your browser; nothing is kept on the server
├─ Take on host      written into the backup directory
├─ Schedule          off by default: an interval in hours, and how many to keep
└─ Check / restore   inspect an archive first, then replace the database with it
```

**Where they live.** `/var/opt/nexora/backups` on a native install. In Docker,
the stacks mount `./backups` next to the `docker-compose.yml` you started, so the
archives are on the host and survive the container. Either way, copy that
directory somewhere else — a backup that only exists on the machine it protects
is not a backup.

**Encryption.** A passphrase is optional and applies to the download, to backups
taken on the host and to scheduled ones (scrypt + AES-GCM). The panel stores it
only to encrypt with; it cannot recover a lost one, and an archive that cannot be
decrypted cannot be restored — so keep the passphrase where you keep the archives'
destination, not on the panel.

**Checking before restoring.** *Check* reads an archive without touching
anything: what it holds, when and by which panel version it was taken, and any
warnings — an archive from another host (its licence will not validate here), one
carrying no main admin, one taken without the traffic history or the audit log.

**Restoring.** A restore replaces every row in the database and restarts the
panel. Before it does, it writes a **pre-restore snapshot** of the current
database into the same directory; retention never deletes those, so a restore
that turned out to be wrong is undone by restoring the snapshot. By default a
restore keeps *this* install's own address settings (port, domain, path, TLS) and
its licence, so restoring an archive from another machine does not point the
panel at an address this server does not have.

**Moving to another server.** Install the panel on the new server, open the setup
link, and on the wizard's first screen follow *Moving from another server? Restore
a backup* instead of filling the form in. This is the one place a restore works
before an account exists — which is exactly the state a fresh install is in — and
here the archive's own settings are taken, because the empty install has none
worth keeping. The licence does not travel: it is bound to the host's
fingerprint, so install your key on the new server (`nexora-panel hwid` prints
the fingerprint it needs).

**From the command line**, for a headless or scripted install:

```bash
nexora-panel config set backup_enabled true
nexora-panel config set backup_interval_hours 24    # daily
nexora-panel config set backup_keep 14              # 0 keeps everything
nexora-panel config set backup_dir /var/opt/nexora/backups   # must be absolute
nexora-panel config set backup_passphrase "a long passphrase"
```

The schedule is read on the panel's next hourly tick, so none of these needs a
restart. `backup_passphrase` is never printed back by `config list` or `config
get`. In Docker, prefix these with `docker compose exec panel /app/`.

**Restoring from the command line**, for the case the panel is not running at
all — the database lost, or the panel failing to start:

```bash
systemctl stop nexora-panel
nexora-panel restore /var/opt/nexora/backups/nexora-backup-20260914-030000.tar.gz
systemctl start nexora-panel
```

It reads the archive first and prints what it holds and any warnings, then asks
you to type `replace-database`. A run with no terminal — a script, a pipe —
takes `-yes` instead of the question. An encrypted archive takes `-passphrase`,
or asks for it. As in the panel, this install's own address settings and licence
are kept (`-keep-web-settings=false` and `-keep-license=false` take the
archive's), and a pre-restore snapshot is written before anything changes.

Stop the panel first. On SQLite the swap happens the next time the panel starts,
so whatever a still-running panel writes in the meantime stays behind in the
replaced database; on PostgreSQL the rows are replaced immediately, underneath
it.

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh) --uninstall
```

The service and `/opt/nexora-panel` are removed. Your database *and your backups*
in `/var/opt/nexora` are deliberately left behind; delete them yourself when you
are sure you no longer need them — and copy `/var/opt/nexora/backups` off the
server first if the server itself is going away.

## Where things live

| Path | What |
| --- | --- |
| `/opt/nexora-panel/nexora-panel` | the binary |
| `/opt/nexora-panel/config.json` | database connection only |
| `/var/opt/nexora/nexora.db` | the SQLite database |
| `/var/opt/nexora/bin/` | node binaries the panel serves to node installers |
| `/var/opt/nexora/sub-themes/` | subscription page themes |
| `/var/opt/nexora/presets/` | preset catalogue files, merged onto the one the panel ships |
| `/var/opt/nexora/backups/` | backup archives and pre-restore snapshots (mode 0700) |
| `/var/opt/nexora/rulesets/` | mirrored rule-set files the panel serves to its nodes |
| `/etc/systemd/system/nexora-panel.service` | the service unit |

Everything else — admins, settings, certificates, nodes, users — lives in the
database and is managed from the panel.
