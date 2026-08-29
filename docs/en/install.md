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
- An open TCP port for the panel (2095 by default).

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
when your panel serves a large user base.

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
    not listed, add it.
  - Add a domain and the certificate is reissued to cover it; a subscription
    domain rides on the same certificate.
  - You may turn HTTPS off, but then passwords and subscription links travel in
    clear text.
- **Time zone** — what every timestamp in the panel is rendered in.

Saving restarts the panel onto the address you just described, and the browser
follows it. With a self-signed certificate your browser warns once — accept it
and continue.

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

In Docker the panel's port is pinned by `NEXORA_WEB_LISTEN` in the compose file,
because the published port mapping lives there too. Changing the port in the
panel UI would only make the container unreachable, so change both together.

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
nexora-panel config set web_domain ""          # stop restricting the hostname
nexora-panel config set web_basepath ""        # serve at the root again
systemctl restart nexora-panel
```

The installer puts `nexora-panel` on your PATH and the binary finds its own
config file, so these work from any directory. In Docker, prefix them with
`docker compose exec panel /app/`.

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh) --uninstall
```

The service and `/opt/nexora-panel` are removed. Your database in
`/var/opt/nexora` is deliberately left behind; delete it yourself when you are
sure you no longer need it.

## Where things live

| Path | What |
| --- | --- |
| `/opt/nexora-panel/nexora-panel` | the binary |
| `/opt/nexora-panel/config.json` | database connection only |
| `/var/opt/nexora/nexora.db` | the SQLite database |
| `/var/opt/nexora/bin/` | node binaries the panel serves to node installers |
| `/var/opt/nexora/sub-themes/` | subscription page themes |
| `/etc/systemd/system/nexora-panel.service` | the service unit |

Everything else — admins, settings, certificates, nodes, users — lives in the
database and is managed from the panel.
