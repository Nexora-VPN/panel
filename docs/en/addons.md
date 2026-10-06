# Installing addons

Addons are separate programs that work beside the panel — a shop, a bot, a
report. The panel finds them in the **addon directory** at
[addons.nexora-panel.org](https://addons.nexora-panel.org), installs them on a
server of yours — by a command you run, or by itself — over SSH, or on its own server with none — and registers
them once you have approved what they ask for. How a registered addon is
looked after (health, suspend, updates of its permissions, removal) is in
[Panel services → Addons](services.md#addons).

| | |
| --- | --- |
| [The directory](#the-directory) | what is listed, and how far each addon is trusted |
| [Installing by command](#installing-by-command) | the panel gives you one command to run |
| [Installing over SSH](#installing-over-ssh) | the panel installs it on a server itself |
| [On the panel's own server](#on-the-panels-own-server) | the panel installs it beside itself, with no SSH |
| [A certificate from the panel](#a-certificate-from-the-panel) | HTTPS for an addon with no port 443 of its own |
| [The addon's own certificate](#the-addons-own-certificate) | `self-signed`: the panel trusts the certificate you approve |
| [Updating](#updating) | the badge, and updating where the addon runs |
| [Removing](#removing) | from its server, and from the panel |
| [A mirror of the directory](#a-mirror-of-the-directory) | when addons.nexora-panel.org is out of reach |

## The directory

*Services → Addons → Browse* lists what the directory holds. Each addon is in
one of three tiers:

| Tier | What it means | How it can be installed |
| --- | --- | --- |
| **Official** | made by Nexora, its manifest signed with Nexora's key | by command or over SSH |
| **Verified** | from another developer, reviewed by Nexora, signed with a key the directory vouches for | by command or over SSH; the consent screen names the developer |
| **Unofficial** | listed after a light check only | by command only, with a warning on the card and on the consent screen |

The panel reads the directory once a day with its release check, and when
you press *Read now*. The list it reads is signed with the directory's own
key; the panel refuses one that is not, or that is older than the one it
already has. With the daily release check switched off (*Settings → Update*)
the directory is read only when you ask.

## Installing by command

Pick an addon, then **Install**. The form is built from the addon's own
manifest:

1. **How** — *As a service* (its binary under systemd, no Docker), *With
   Docker* (its image, through its install script), or *Compose file* (for an
   addon that ships only a compose file).
2. **Where the panel will reach it** — the addon's address once it runs, as
   this panel sees it. Plain `http://` only on a private address. While the
   addon's HTTPS answer is on, the form proposes its public address with the
   admin path: the panel reaches it there, over HTTPS.
3. **Where it reaches the panel** — this panel's address as the addon's server
   sees it.
4. **Its questions** — a port, a database, a token: exactly what the addon
   declares, each with its type. A question that depends on another appears
   only when it applies. An admin password takes 10 characters to 72 bytes
   (about 36 Persian or Russian letters, 24 Chinese); the form says so, and
   `install.sh` refuses one outside that for a command install.

**Make the command** checks the answers, makes a one-time claim code and gives
one command to run **as root on the addon's server**. If one of the answers is
a secret, the command carries it and is shown only this once — copy it before
closing; the panel never stores your answers.

Then the panel waits for the addon to answer at its address. Once it does, it
shows what the addon asks for — each permission of its token with the reason,
each event — and **Approve and register** registers it with the claim code it
already has: nothing to copy back. You can close the form meanwhile; the
install stays under *Waiting for an addon to answer* with **Continue**, for a
week.

An addon that carries no signature this panel trusts ends at *Add your own
addon*, filled in: you create its token and webhook there yourself.

## Installing over SSH

For an official or verified addon, **Who runs it** offers *The panel, over
SSH* — the same way the panel installs a node:

- **Host**, **SSH port**, **User** (root, or a user with sudo), and a
  **password** or **private key**. They are used for this connection only and
  never stored. The server's host key is remembered on first contact.
- **Release files** — *The panel brings them*: the panel downloads the
  release, checks it against the release's `SHA256SUMS` and uploads it, so the
  server needs no access to GitHub. *The host downloads them*: the install
  script fetches the release on the server.
- **Authorise the panel's key on this host** — so updating and removing it
  later need no password. Leave it off and you are asked again each time.

**Install** runs the addon's install script on the server and shows its log
live. The addon then registers as above: review and **Approve and register**.
To install on the panel's own server, see
[On the panel's own server](#on-the-panels-own-server); when the panel runs in
Docker, its host is one more SSH target.

The panel checks the server first (its architecture, systemd or Docker) and
stops with the reason before writing anything if the addon cannot run there.

## On the panel's own server

When the panel runs directly on a Linux server (not in Docker), **Who runs
it** offers *The panel, on this server* first, and picks it: the panel runs
the addon's install script itself, as root, with no SSH and nothing to type.
The release is checked against its signed `SHA256SUMS` exactly as over SSH,
and **Where the panel will reach it** fills in as `http://127.0.0.1:<port>` —
or, while the addon's HTTPS is on, as its public address.
A panel in Docker does not offer it — it would install into its own
container — and says why; install by command or over SSH there.

An addon installed over SSH on the panel's own server moves to this kind of
install with **Update on its host** → *This host is the panel's own server:
run it here, with no SSH*. The panel refuses that for any other server.

On the panel's server the addon takes its HTTPS certificate from the panel
(below): an ACME certificate of its own would need the port 80 or 443 the
panel or a node already holds, so the form does not offer it there.

## A certificate from the panel

An addon whose HTTPS answer offers **panel** — Shop and the notifier do —
serves its public address with a certificate from the panel's own store
(*Certificates*). The panel issues and renews it; the addon fetches it from
the panel every few minutes (by its claim code before it registers, by its
token after) and keeps a copy, so it comes up with HTTPS even while the panel
is down. It needs no ACME of its own, so it listens on any port, and several
addons share one server with the panel.

- In the install form, answer **HTTPS certificate: panel** and choose the
  certificate. *Make one on the Certificates page* opens the store in a new
  tab; reload the list when it is made.
- For an addon on another server only certificates issued by **dns-01**,
  **self-signed** or **uploaded** ones are offered: http-01 and tls-alpn-01
  prove the panel's server, not the addon's.
- The addon serves HTTPS on its install **port** alone, with no plain-HTTP
  port beside it, and the public address names that port (443 when it names
  none): where 443 is taken, answer port 8443 with the public address
  `https://shop.example.com:8443`. The form and `install.sh` refuse a public
  address on another port. In Docker, compose publishes that port as it is.
- Change or clear it later on the addon's row: **Certificate**.
- The panel trusts a self-signed certificate it gave an addon when it reaches
  that addon over https; browsers warn, as with any self-signed one.

The other answers stay, on the same one port: **acme** (the addon gets its
own, answering the CA on its port, so the port is 443 — `install.sh` refuses
another; choose acme-http or panel there), **acme-http** (the same on any
port, the CA asking on port 80, which is published only in this mode),
**self-signed** ([below](#the-addons-own-certificate)) and **off** (plain
HTTP on the port, for a reverse proxy of yours). An addon installed before
this keeps its two ports when it is updated: nothing to do.

## The addon's own certificate

With **self-signed** the addon serves a certificate it made itself, which
neither a CA nor the panel vouches for. At the consent screen the panel shows
that certificate's SHA-256 fingerprint with a warning: compare it with the one
the addon's Set-up page shows; approving trusts exactly that certificate.

The addon renews it about once a year (397-day certificates, renewed 30 days
before they end). The panel then no longer trusts it — its health fails,
saying the certificate is not trusted — and an addon added by hand starts
out that way. In the addon's row menu, **Certificate** shows **What it
serves now** with its fingerprint; compare it, then **Trust this certificate**.

For an address by IP, **panel** with a self-signed certificate from the
panel's store needs none of this: the panel trusts its own certificates.

## Updating

When the directory has a newer version of a registered addon, its row on the
*Registered* tab shows it (*0.2.0 in the directory*) and the Addons menu gets a
dot.

- **Installed over SSH or on this server:** **Update on its host** runs the install script again
  on that server. Its settings and data are kept, and the panel reads the new
  manifest at once.
- **Installed by command:** on its server, run its install script again
  with no arguments — `sh nexora-addon-install.sh` installs the latest release
  the same way, keeping the answers and the data. For a *Compose file*
  install, set `NEXORA_ADDON_VERSION` in its `.env` to the new version, then
  `docker compose pull && docker compose up -d`.

A new version that asks for more permissions or events is installed, but
waits for your approval before it gets them — see
[updates](services.md#addons).

## Removing

**Remove from its host** (an addon installed over SSH or on this server) runs its install script
with `--uninstall` on that server; tick *Delete its data too* to remove its
data directory as well — that cannot be undone. The addon stays registered on
the panel until you also **Remove** it there; removing it there tells the addon
first, then deletes its token and webhook.

By hand, on the addon's server:

```sh
sh nexora-addon-install.sh --uninstall           # keeps its data
sh nexora-addon-install.sh --uninstall --purge   # deletes it too
```

An addon removed with its data kept and installed again from the panel (a
new install, a new claim code) registers as any other: it sees the new claim
code, drops the registration it kept and sets its admin's password to the
new install's answer. An update or a restart keeps both. An addon from an
older release answers *already registered* (409) instead; the panel says
what to do: install it again from the panel, or remove it with its data
first.

## A mirror of the directory

Where addons.nexora-panel.org cannot be reached, point the panel at a copy of
its `index.json` with **Change source** on the *Browse* tab. Any copy is safe:
the panel checks the directory's signature on it, so a mirror can serve the
list but cannot change it. Empty goes back to addons.nexora-panel.org. Over
SSH with *The panel brings them*, the release files come from GitHub through
the panel, so only the panel needs to reach it.
