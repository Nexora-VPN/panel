# Installing addons

Addons are separate programs that work beside the panel — a shop, a bot, a
report. The panel finds them in the **addon directory** at
[addons.nexora-panel.org](https://addons.nexora-panel.org), installs them on a
server of yours — by a command you run, or by itself over SSH — and registers
them once you have approved what they ask for. How a registered addon is
looked after (health, suspend, updates of its permissions, removal) is in
[Panel services → Addons](services.md#addons).

| | |
| --- | --- |
| [The directory](#the-directory) | what is listed, and how far each addon is trusted |
| [Installing by command](#installing-by-command) | the panel gives you one command to run |
| [Installing over SSH](#installing-over-ssh) | the panel installs it on a server itself |
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
   this panel sees it. Plain `http://` only on a private address.
3. **Where it reaches the panel** — this panel's address as the addon's server
   sees it.
4. **Its questions** — a port, a database, a token: exactly what the addon
   declares, each with its type. A question that depends on another appears
   only when it applies.

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
To install on the panel's own server, give that server's address — when the
panel runs in Docker too, its host is one more SSH target.

The panel checks the server first (its architecture, systemd or Docker) and
stops with the reason before writing anything if the addon cannot run there.

## Updating

When the directory has a newer version of a registered addon, its row on the
*Registered* tab shows it (*0.2.0 in the directory*) and the Addons menu gets a
dot.

- **Installed over SSH:** **Update on its host** runs the install script again
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

**Remove from its host** (an addon installed over SSH) runs its install script
with `--uninstall` on that server; tick *Delete its data too* to remove its
data directory as well — that cannot be undone. The addon stays registered on
the panel until you also **Remove** it there; removing it there tells the addon
first, then deletes its token and webhook.

By hand, on the addon's server:

```sh
sh nexora-addon-install.sh --uninstall           # keeps its data
sh nexora-addon-install.sh --uninstall --purge   # deletes it too
```

## A mirror of the directory

Where addons.nexora-panel.org cannot be reached, point the panel at a copy of
its `index.json` with **Change source** on the *Browse* tab. Any copy is safe:
the panel checks the directory's signature on it, so a mirror can serve the
list but cannot change it. Empty goes back to addons.nexora-panel.org. Over
SSH with *The panel brings them*, the release files come from GitHub through
the panel, so only the panel needs to reach it.
