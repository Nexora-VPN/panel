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
- An open TCP port for the panel. The installer picks a free high port at
  random and prints it with the setup link; the Docker image uses 2095. The
  panel binds the IPv6 wildcard, which serves IPv4 as well, so a v4-only,
  v6-only or dual-stack server all work unchanged.

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
http://203.0.113.10:28431/setup?t=9f3c1ad2…
```

That port is different on every install: the installer picks a free one at
random the first time, so a panel that nobody has set up yet is not waiting on
the number a scanner sweeps for. If a firewall is running, open that port. The
wizard can move it before you finish, and **Settings → Panel** afterwards.

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
`http://[2001:db8::10]:28431/setup?t=…`. Paste it whole; a browser will not
accept it without the brackets.

If you lose the links, print the token again on the server and rebuild a URL
around it:

```bash
nexora-panel setup-token          # → 9f3c1ad2…
nexora-panel config get web_listen_port
# → 28431       then open http://YOUR-SERVER:28431/setup?t=9f3c1ad2…
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

## Getting around it

Two things worth knowing on your first day, because neither is where you would
look for it.

**Press Ctrl-K** (Cmd-K on a Mac) anywhere in the panel, or click the magnifier
in the header. One box searches every page, every "new …" form, and your users
— by name, by group, and **by subscription id**, which is what turns "a
customer sent me this link and nothing else" into one paste. Arrows move, Enter
opens, Escape puts you back exactly where you were. A plain `/` opens it too,
whenever you are not typing into a field.

**Install the panel as an app.** In Chrome, Edge or Android's browser, the
address bar offers to install it; on an iPhone use Share → Add to Home Screen.
It then opens in its own window with no address bar, and works at a base path
like `/panel` exactly as it does at the root. It is the same panel in a
different frame: there is no offline mode, because every page of a control
plane is a live read of a fleet that changes while you are looking at it.
Installing needs HTTPS — a panel reached over plain `http://` on an address
simply will not offer it.

The colour and the density are in the theme menu beside the language switch:
five palettes, and a compact mode that fits noticeably more rows on a laptop
screen. Both are per browser, not per account.

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

**Put a `404.html` in it too.** Any path in that directory with no file behind
it answers 404, and without a `404.html` what it answers is the Go web server's
own `404 page not found` in plain text — which identifies the software on the
first probe a scanner sends, and that is the signature the disguise is here to
remove. With a `404.html` in the directory it is served instead, with the same
404 status. A directory without one behaves exactly as it did before.

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

The panel checks once a day whether a newer release exists and shows a banner
when there is one. **Settings → Panel update** has the whole story: the
installed version against the newest release, how this panel was installed, and
— on a systemd install — a button that does the upgrade:

1. takes a database backup into your backup directory,
2. downloads the release and checks it against the checksum published with it,
3. runs the downloaded binary once, to be sure it is a panel that starts on
   this machine,
4. swaps it in, keeping the old one at
   `/opt/nexora-panel/nexora-panel.previous`,
5. restarts. You stay logged in; the panel is unreachable for a few seconds and
   the page says when it is back.

If the new build does not come up, the previous binary is put back
automatically — within about ten seconds, not minutes. **The database is not
rolled back**: migrations only ever go forward. So if something looks wrong
after an upgrade, the backup taken in step 1 is the way back, under
**Settings → Backup**.

A Docker install cannot replace its own image, and the page says so rather than
half-trying. Update it the usual way:

```bash
docker compose pull && docker compose up -d
```

The daily check is one request to this repository's releases, which tells
GitHub your server's address. Turn it off with the switch on that page, or from
the command line:

```bash
nexora-panel config set update_check false
```

The button on the page still works with the check off — that setting is about
what the panel does on its own, not about what you may ask it for.

### From the command line

Run the installer again. It detects the existing install and updates in place:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nexora-vpn/panel/main/install.sh)
```

It stops the service, backs up a SQLite database to `nexora.db.bak`, keeps the
previous binary at `/opt/nexora-panel/nexora-panel.previous`, migrates, and
starts again. Your `config.json`, settings and admin accounts are untouched. If
you use PostgreSQL, take your own dump first.

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
nexora-panel admin list                        # which accounts exist, and which one owns the panel
nexora-panel admin reset-password              # the owner; the password is typed in, not echoed
nexora-panel admin reset-password -user alice  # any other account
```

With no `-user` it takes the panel's **owner** — the one account that cannot be
deleted or demoted, which `nexora-panel admin list` marks, so "the main admin"
has a single answer even when there are several. On an install that predates the
owner it falls back to the only main admin, and refuses — naming them — if there
is more than one. The new password is asked for twice and never echoed;
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

Nothing here needs configuring for it. The panel listens on the IPv6 wildcard —
`[::]` on whichever port it was given — which on a dual-stack host answers IPv4
too; a host with IPv6 switched off cannot bind that and the panel falls back to
`0.0.0.0` on the same port by itself. To bind one family only, set
`web_listen_ip` to a literal address (`::` or `0.0.0.0`, or one specific
address) in the wizard or from the command line.

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

### XHTTP: the advanced fields

An XHTTP inbound's **Advanced** fields are the knobs Xray-core's transport has,
under sing-box spellings. Every one of them is enforced by the node *and* told
to the client in its link, so the two ends agree — which has one consequence
worth reading twice: **change any of them and every link for that inbound must
be re-issued.** A client still holding the older link is refused by the node,
and XHTTP refuses with intermittent 4xx rather than a clean failure, so what
reaches your support chat is "it works sometimes". Settle these before customers
import the inbound, or plan a re-import.

What they do:

- **X-Padding bytes** — the size range of the padding both ends add to every
  request, `100-1000` by default. Wider means more bytes per request and less
  regular sizes. The node answers 400 to padding outside its range, which is
  why the value has to travel in the link.
- **X-Padding obfuscation**, with its **key, header, placement and method** —
  off, the padding is a fixed `Referer`/`x_padding` pair and the four fields
  are ignored. On, it moves into a header, a query parameter, a cookie or the
  path (placement), under a name you choose (key/header), generated by one of
  two methods (`repeat-x`, `tokenish`).
- **Session placement/key** and **Sequence placement/key** — where the session
  id and the packet sequence travel: a path segment (default), a query
  parameter, a request header or a cookie, under the key you name.
- **Uplink HTTP method**, **data placement** and **data key** — how the client
  sends its upload half: `POST` bodies (default), or `GET` with the data in a
  header or a cookie.
- **Max bytes per post** — the largest upload chunk, `1000000` by default.

Only the values you changed go into the link; a default never does. That way a
later change of default, ours or Xray's, applies to old links and new alike
instead of pinning today's number into every link ever minted.

**Behind a CDN**, padding, session id and sequence travel in every placement:
they are short values in a path, a query, a header or a cookie, which any CDN
that forwards HTTP forwards. The two shapes a CDN cannot carry are the uplink
*payload* in a **header** or in a **cookie**, and the panel refuses those when
you save the front — see [what cannot be
fronted](subscriptions.md#what-cannot-be-fronted-and-what-to-do-instead).

**Who reads them.** Xray-based clients — v2rayNG, v2rayN, Streisand, Happ —
speak XHTTP and get every field. sing-box and Clash apps have no XHTTP, so their
subscription files leave the inbound out rather than carry half of it.

**One field the form does not offer** — `trusted_x_forwarded_for`, in the
inbound's JSON under `transport` — matters the moment an XHTTP inbound sits
behind a CDN or a reverse proxy. It lists the request headers the node is to
trust — normally the one a CDN writes the client's address into
(`CF-Connecting-IP` for Cloudflare). On a request that carries one of them, the
first one in the list it carries decides: if its value is an IP address, that
is the client's address — the one the address limit and the logs see. A header
whose value is not an address (a secret your proxy adds) only marks the
request, and the node then reads the first `X-Forwarded-For` entry, which the
client can write itself: a marker never gives an address you can rely on. A
request carrying none of them has no address but the connection's own. **Empty
means trust any** `X-Forwarded-For`, from anyone — a client on a directly
reachable inbound can then name its own source address. Xray-core changed its
own default to *trust none* in 26.6.22; this node kept the older rule. **The
panel fills the field for you when a front says which header its CDN writes the
client address into** (the front's *client address header*, `CF-Connecting-IP`
for Cloudflare): every XHTTP inbound that front is enabled on gets it, unless
the inbound sets its own. So name the header on the front, and leave an inbound
that has no front behind nothing else. The address is then only as good as
three things: the header's value must come from the CDN, not the client
(Cloudflare writes it itself; Fastly passes a client's `Fastly-Client-IP` on
unless you configure it not to — check your CDN's documentation); the node must
accept connections from the CDN alone, since a client that reaches it directly
can send the header too; and every front on the inbound must name the same
header, since a CDN passes another CDN's header on unchanged. With all three,
the address can back limits; without them, treat it as a hint.

### VLESS Encryption

A VLESS inbound can encrypt the VLESS stream itself — **VLESS Encryption**, on
the inbound's **Protocol** tab — inside TLS or with no TLS at all. Two things it
buys that nothing else on the panel does: where a CDN terminates TLS (the
fronting on the Fronts page), the CDN sees ciphertext instead of your VLESS
traffic; and every connection runs a post-quantum key exchange (ML-KEM-768 with
X25519), TLS or not.

Turn it on by picking an **authentication** — which key proves the server:
**X25519** (not post-quantum) or **ML-KEM-768** (post-quantum). Pick one; the
exchange inside each connection is post-quantum either way. The panel mints
the key, stores the server string as the inbound's `decryption`, sends it to
the node, and derives the client string every link and outbound carries. The
server string never appears in a link. **Mode** (`native`, `xorpub`, `random`)
decides how much of the handshake is hidden behind XOR streams; **ticket
lifetime** is how long a client can reconnect without a full handshake.

Two rules travel with it. **It re-issues every link**: a client holding a link
from before the change is refused at the handshake, so set it before customers
import the inbound, or plan a re-import — the same rule as XHTTP's advanced
fields. And **sing-box apps cannot use it** (Karing, NekoBox, SFA — sing-box
closed the request), so their subscriptions leave the inbound out rather than
carry one that cannot connect; Xray-core apps (v2rayNG, v2rayN, Streisand,
Happ) and mihomo 1.19.14+ get it in full. One more: `xtls-rprx-vision` is
dropped on an encrypted inbound, on the node and in the links alike — the
node's VLESS service runs vision only directly on a TLS connection.

### Port hopping

A Hysteria or Hysteria2 inbound can listen on a set of ports beside its own —
**Listen ports**, in sing-box's `start:end` spelling, e.g. `20000:20999` — and a
client that knows the set moves between them, so a blocked port costs one port.
The node answers on all of them without an iptables redirect, and the link
carries the set (`mport=` in a share link, `server_ports` in a sing-box file,
`ports` in a Clash one).

How often the client moves is the client's decision, not the node's, so it
lives in the inbound's **Client** tab: **Hop interval** (`30s` in every client
that is told nothing) and, for Hysteria2 only, a **maximum** — with both set, a
client draws each hop at random between the two, so the moves stop being
periodic. Both reach the sing-box file (`hop_interval`, `hop_interval_max`) and
the Clash file (`hop-interval`, a number, or `30-60` once a maximum is set —
mihomo reads the range since 1.19.24). A share link has no field for either, so
a client importing the link keeps its own default. The panel refuses at save
time what a sing-box client would refuse at start-up, on the customer's device:
a maximum without an interval, a maximum below it, or anything under five
seconds.

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

**Block torrents** is best-effort, and its dialog says so. It sniffs each
connection and sends what looks like BitTorrent to a block outbound the node
counts, so the figure is on the node's row, in `/metrics`, and — above a rate
you set — in a `node.rejections_high` event. Sniffing is protocol detection,
not a guarantee: a client that encrypts its handshake (MSE/PE, on by default in
most of today's clients) or one the sniffer has not seen passes. Panels that
promise more run a deep-packet-inspection engine beside the core; this one does
not. Read the counter as what was caught, not what there was.

**Iran + block ads** is as good as the list, and the list is not complete. It
sends `geoip-ir` and `geosite-category-ir` out at the node, so domestic traffic
stays local — for the prefixes the SagerNet set knows about. Measured on
2026-09-22, the fuller community set,
[Chocolate4U/Iran-sing-box-rules](https://github.com/Chocolate4U/Iran-sing-box-rules),
carries about 12% more Iranian prefixes (343), with hosting providers such as
ParsPack the least covered. Nothing is broken and the preset does what it says.
But if the reason you apply it is that no domestic destination should ever
leave through the node, add the fuller list yourself: a catalogue file in the
presets directory (above) that re-points `geoip-ir` at
`https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geoip-ir.srs`,
and the panel mirrors it like any other.

## When the whole internet is cut

On a day the international link is cut rather than filtered, nothing in this
panel helps: every inbound needs a route out, and there is none. What has kept
working through such days is DNS — resolvers inside the country still forward
queries out, slowly — and the tool for that is a **DNS tunnel run beside the
node**, not inside it. The panel deliberately has no page for it: a feature for
a day that comes once a year is a support burden the rest of the year, and the
tools that exist are a shell script away.

The shape: on the node's server,
[dnstt-deploy](https://github.com/bugfloyd/dnstt-deploy) (dnstt — slow, robust,
UDP/53) or [slipgate](https://github.com/anonvector/slipgate) (dnstt and
Slipstream, the faster QUIC-over-DNS one, under one manager) installs the tunnel
server as a systemd unit. Point its target at an inbound that listens on
loopback — a SOCKS or Shadowsocks inbound with `listen` set to `127.0.0.1` on
the same node, given to the same users — so the tunnel hands its connections to
the node and every byte is still counted per user. (Every connection then
arrives from `127.0.0.1`, so the address limit sees one address for everyone
behind the tunnel.) The DNS side needs an NS record delegating a subdomain,
`t.example.com`, to the server, and port 53 free on it — a node binds nothing
there; the DNS presets name remote resolvers.

The client apps — NetMod, HTTP Injector, SlipNet, the dnstt app — ask for three
values, and all three are the tunnel's, not the panel's: the tunnel domain, the
server's public key the installer prints, and a resolver to send the queries to
(a DoH or DoT URL on an ordinary day; a plain domestic resolver's address on the
cut-off one). Through the tunnel the app then speaks to your loopback inbound
exactly as it would to a public one, so what it needs from you is that inbound's
link with the address replaced by the local endpoint the app exposes.

## Links and subscriptions

Once the fleet is up, what your customers receive is its own subject:
**[links and subscriptions](subscriptions.md)**. It covers advertising several
addresses per node, putting a CDN in front of an inbound (including the wildcard
DNS record a per-customer hostname needs, and why the panel refuses to front a
REALITY or Hysteria inbound), naming the entries from a template, and the one
client setting — **Mux**, in Xray-based apps — that silently breaks these
configurations.

## Operators and roles

**Settings → Admins** creates operator accounts; **Roles** decides what each one
can do. Three roles ship with the panel and cover most installs:

| Role | What it is for |
| --- | --- |
| Main admin | Runs everything, including the panel's own administration: operators, roles, API tokens, the licence, backups and the security settings. |
| Operator | Runs the service: users, nodes, templates, the pool, certificates and settings — but not the panel's administration. |
| Reseller | Owns a book of users and nothing else. Its traffic allowance, expiry and user cap are set on the account. |

A **custom role** starts from one of those three and takes permissions away. It
can never add any: the panel refuses to store a role granting a permission you
do not hold yourself, and refuses to put an account on one. So an "operator who
may not touch the nodes" is a role, and an "operator who may also manage the
licence" is not.

Two things decide what an account reaches, and they are different questions:

- **Permissions decide which pages.** A role that is not given "Configure nodes"
  can open the node list if it was given "See nodes", and every button on it
  answers "your role is missing the nodes:write permission".
- **Ownership decides which users.** A reseller sees the accounts it owns and no
  others — that is a property of being a reseller, not a permission. Giving a
  reseller role "See users" does not show it anybody else's customers.

A role can also carry **limits**, which are not permissions: how many users an
account on it may own, the highest device limit it may give a user, and the
longest plan it may sell. `0` means no limit. A limit is a ceiling over the
account's own allowance — it never raises one — and a user left with *no* device
limit at all is refused rather than quietly capped, because "no limit" is a real
choice here and it should not be made for you.

Editing a role signs out everybody holding it; they get the new permissions on
their next login. A role held by any account cannot be deleted, and the refusal
names the accounts so you know where to look. The three built-in roles are
always present and cannot be edited or deleted — only their limits can be set.

**The owner.** One account owns the panel. It cannot be deleted or demoted, and
it is the only account that can hand the panel to another main admin (the crown
icon in the admin list). Handing over is a *transfer*: you stay a main admin,
but from then on only the new owner can hand it on. On an existing install the
owner is the oldest main admin, chosen for you — nothing to set up.

The owner is also what `nexora-panel admin reset-password` resolves to when you
give it no account name, which is why `nexora-panel admin list` marks it.

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
worth keeping. The licence comes along but stays bound to the old host's
fingerprint: **License → Move the licence to this machine** moves it, with no
key to paste — see [moving to a new server](licence.md#moving-to-a-new-server).

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
