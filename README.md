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

## IPv6

The panel binds `[::]:2095` by default, which serves IPv4 as well — a v4-only,
v6-only or dual-stack server all work with no configuration (on a host with IPv6
switched off the panel falls back to `0.0.0.0` by itself). A node with only an
IPv6 address is added with its address written plainly, `2001:db8::1`, and the
panel brackets it wherever a link, a subscription URL or a client profile needs
it.

## Documentation

- [English](docs/en/install.md)
- [فارسی](docs/fa/install.md)
- [Русский](docs/ru/install.md)
- [中文](docs/zh/install.md)

## Releases

| | |
| --- | --- |
| Linux | `nexora-panel-linux-{amd64,arm64,armv5,armv6,armv7,386,s390x,riscv64}.tar.gz` |
| Windows | `nexora-panel-windows-{amd64,arm64}.zip` |

Each archive contains the `nexora-panel` binary and, on Linux, the systemd unit.

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
