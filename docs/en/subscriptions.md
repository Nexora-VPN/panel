# Links and subscriptions

What your customers actually receive, and the four things that change it: the
addresses a node advertises, a CDN in front of an inbound, what each entry is
called, and what the panel tells the client along with the file.

| | |
| --- | --- |
| [How a subscription is built](#how-a-subscription-is-built) | why one node with three addresses is three entries and not three files |
| [Where the links are published](#where-the-links-are-published) | the subscription domains, a hostname per customer, a domain per reseller |
| [Several addresses per node](#several-addresses-per-node) | a second IP, a domain, an IPv6 address |
| [Domain fronting](#domain-fronting) | putting Cloudflare in front of an inbound |
| [Naming the entries](#naming-the-entries) | the name template and its variables |
| [What the client is told](#what-the-client-is-told) | response headers, the update interval, announcements |
| [Tell your users to turn Mux off](#tell-your-users-to-turn-mux-off) | the one client setting that breaks these configs |

## How a subscription is built

A user's subscription is a list of entries, one per way they can reach your
fleet. The panel walks the nodes that user is provisioned on, and for each
inbound on each node it writes an entry. Then it does the same for the fronts.

The rule worth learning first, because it decides how big the file gets:

> **Addresses and fronts add. They never multiply.**

Three nodes serving one inbound, each node listing two addresses, and two
domain fronts enabled on that inbound:

```
3 nodes × 2 addresses = 6 direct entries
              2 fronts =  2 front entries        ← not 6, and not 12
                          ────────────────
                          8 entries
```

A node address belongs to the **node** — it is another way to reach that one
machine, so it repeats per node. A front belongs to the **inbound** — the CDN
picks which of your servers to talk to by the name it is given, so one front
covers however many nodes serve that inbound, and it is written once.

Everything below changes that list. Link addresses, fronts and entry names are
all read when a client fetches its subscription, so an edit is live on the next
fetch with nothing to sync. The one exception is a front's *client address
header*: a save or a delete that changes which header an XHTTP inbound trusts
is sent to every node serving that inbound, which restarts the inbound there
and drops its live connections. Any other edit reaches no node.

## Where the links are published

Before any of that: the address the file is fetched *from*. It is a different
thing from the panel's own address and the panel keeps the two apart on purpose
— the panel prefix is meant to stay private, while a subscription URL is handed
to every customer you have.

**Settings → subscriptions → subscription domains.**

Anything listed there serves `/sub`, and on those names the panel is reachable
only at its **base path** — a request for the API or the login page at the root
gets a 404, so the address your customers hold tells them nothing about where the
panel is administered. (With no base path set there is nothing to hide behind, so
those names serve subscriptions and nothing at all else. That is also the one way
this setting can lock you out of the panel; see
[locked out?](install.md#locked-out) in the install guide.)

### Why it is a list

Because a domain being blocked is a thing that happens, and by then the links
are already in your customers' clients.

- **New links are generated on the first domain.**
- **Every domain in the list keeps serving** the links that were issued while it
  was first.

So replacing a blocked domain is: add the new one, move it to the top, and leave
the old one in the list while your customers roll over on their own update
schedule. Removing it from the list is what finally cuts those links off, and
that is your decision to make rather than a side effect of adding the
replacement.

### What each one needs

A DNS record pointing at the panel, and a place on the panel's certificate.
Saving the setting reissues the panel's own certificate so it names every domain
in the list. If you manage the certificate yourself — `web_cert_file` /
`web_key_file`, or one from the certificate store — you have to put every name on
it yourself: a domain the certificate does not cover is a TLS error in the
client, not a link that merely renders somewhere else.

At most eight. Leave the list empty and links are built on whatever address the
panel was reached at, which is what a single-server install without a domain
wants.

### A hostname per customer

A domain in that list may be written with a `*`:

```
*.sub.example.com
```

Every subscriber then gets a **different hostname** under it —
`k4m2xr8qvp.sub.example.com` for one, `bt7wz3ncdh.sub.example.com` for the next
— and the panel answers on all of them. One blocked hostname costs **one
customer** instead of your whole book, which is the difference between a support
ticket and a bad week.

What makes it work rather than merely sound good:

- **It is derived, not random.** The label is a hash of the account, so a
  customer who re-fetches gets the same hostname. A name that changed on every
  poll would break every client that has already saved it.
- **It is one-way.** The hash goes in, nothing comes back out: a hostname on a
  blocklist says nothing about the subscription token behind it.
- **It is per domain.** The same customer gets an unrelated label under each
  domain you configure, so blocking one name gives away nothing about the
  replacement.

**You need one wildcard DNS record**, `*.sub.example.com`, pointing at this
panel. There is no way around it and nothing can warn you it is missing: without
the record the hostnames resolve for nobody, which looks exactly like the domain
being blocked. The panel's own certificate covers the wildcard automatically;
if you manage the certificate yourself, it needs the `*.sub.example.com` name on
it.

Exactly one label is served. `abc.sub.example.com` works,
`a.b.sub.example.com` does not — that is what a wildcard DNS record resolves and
what a wildcard certificate covers, so anything deeper could not be reached
anyway.

A plain entry is untouched by any of this. An install that wants one hostname
for everybody needs no DNS work and renders exactly what it did before.

### A domain per reseller

**Admins → the reseller → edit → subscription domain**, which only the main
admin can set.

It decides which of your configured domains that reseller's customers are
published under. Left alone, they get the first one. A reseller cannot change
its own — a domain is exactly the unit that gets blocked, so choosing one is
choosing whose customers go down together, and that is not a reseller's call to
make about somebody else's book.

The two mechanisms stack rather than compete: with a wildcard domain per
reseller, one blocked hostname costs one customer, and a blocked *domain* costs
one reseller.

If you remove a domain that a reseller was assigned, that reseller falls back to
the first configured one rather than to nothing. Retiring a domain is already
how you take it out of service and it must not take a reseller's whole book
offline as a side effect.

### One detail about rule sets

Nodes download mirrored rule sets from this same published address, and a node
dials a name — `*.sub.example.com` is not one. So the mirror uses the first
**plain** domain in your list, and if every entry is a wildcard it uses
`rulesets.sub.example.com`, which your wildcard DNS record and your certificate
already cover. The rule sets page shows the address it settled on.

## Several addresses per node

**Nodes → the node's row → edit → Link addresses.** Up to four.

Each row is an address — an IP, a domain, an IPv6 address written plainly — with
an optional label. Every address adds one copy of every entry that node
contributes, so a node with three addresses gives each of its inbounds three
entries.

```
Link addresses
├─ Direct     203.0.113.10
├─ CDN        cdn.example.com
└─             2001:db8::10
```

What each part is for:

- **The first row is the primary.** Endpoints (WireGuard, OpenVPN,
  OpenConnect), downloadable app configs and tunnels all use it on its own — a
  `.conf` file is saved once and cannot carry alternatives. Reordering the list
  therefore changes what those get.
- **The label names the entry.** An address with a label suffixes the entry
  name with it; one without falls back to the address itself. The first address
  suffixes the name *only* when it carries a label — which is what keeps the
  names your customers have already imported from moving the day you add a
  second address.
- **`nodes.address` is untouched.** That is where the panel dials the node over
  mTLS; these are what goes into client links. They are allowed to be
  completely different, which is the point: the panel can reach a node on a
  private address while customers reach it through a public one.

A tunnel dials **every** address of its target as failover, all under one peer
name, so a blocked address costs the links it was carrying rather than the
tunnel. Both stay connected — there is no cold standby to warm up.

## Domain fronting

A domain front is a **CDN hostname your customers dial instead of the node**.
The CDN terminates TLS, works out which origin to forward to from the name it
was given, and opens its own connection to your server. To a network watching
the customer, the connection goes to Cloudflare.

**Domain fronting** in the sidebar is the catalogue: up to eight fronts, each
one enabled on the inbounds it fronts. The same membership is editable from the
other end, in an inbound's own **Domain fronting** tab — it is one list, seen
from whichever page you are on. An inbound carries at most four.

### Setting one up

| Field | |
| --- | --- |
| **Label** | names the front, and suffixes the entries it renders, so two fronts on one inbound are told apart by something you chose |
| **Address** | the hostname clients dial — the CDN's. `*.cdn.example.com` gives every customer their own (below) |
| **Port** | blank is 443. This is the CDN's port and has nothing to do with the inbound's listen port, which only the origin sees |
| **SNI** | blank sends the front's own hostname, which is what a CDN expects. Fill it in only if your CDN needs a different name at the origin |
| **Host header** | blank follows the SNI |
| **ALPN, fingerprint, allow insecure** | the client's TLS towards the CDN |
| **Origin node** | optional; see below |
| **Inbounds** | which inbounds this front reaches. Only protocols a CDN can carry are offered |

The entry a front renders **replaces** the address, the port, the SNI, the Host
header, the ALPN and the fingerprint, and it **drops** the certificate pin and
any port-hopping range. The pin is not an oversight: a CDN presents its own
certificate, so a pin computed from the one the panel issued would be a
handshake failure with nothing in the client to explain it.

There is deliberately no path on a front. A CDN route's path is the fronted
inbound's own, and the panel already knows it.

On the CDN side you need what any CDN needs: the hostname proxied (orange
cloud, in Cloudflare's terms), pointed at your node's address as its origin,
and — if the inbound speaks plain HTTP behind the CDN — the origin setting that
allows that. Plaintext to the origin is fine and common: the customer's TLS
session is with the CDN, not with your node.

### A different hostname for every customer

Write the address as `*.cdn.example.com` and each subscriber gets their own
hostname under it — `k7m2rq9xdp.cdn.example.com` for one customer,
`bt4njs6wzv.cdn.example.com` for the next.

This is worth doing, because a CDN hostname landing on a blocklist is the most
common way this feature dies. With a wildcard, one blocked name costs one
customer instead of all of them.

**It needs a wildcard DNS record** — `*.cdn.example.com` pointing at the CDN,
proxied like any other. Without it the name resolves for nobody, which looks
exactly like the CDN refusing the connection.

**On Cloudflare, mind how deep the name is.** Universal SSL — the certificate
your zone gets for free — covers `example.com` and **one** label below it,
`*.example.com`. It does not cover `*.cdn.example.com`, which is one label
deeper. Everything else looks right: the record resolves, the orange cloud is
on, the CDN is clearly in the path. What happens is that the edge has no
certificate to present for that name, so the TLS handshake fails there and
nothing ever reaches your node. Either put the wildcard directly under your zone
— `*.example.com`, with the subscription domain living somewhere else — or add
Advanced Certificate Manager or Cloudflare for SaaS, which issue for deeper
names. Other CDNs have their own rule; check what your certificate actually
covers before suspecting the origin.

The label is derived from the customer's own subscription token, not random, so
it is the same every time that client refreshes — a config that churned on
every poll would be worse than no wildcard at all — and different for every
customer. It is a one-way function of the token: a hostname on a blocklist says
nothing about the token behind it.

### Origin node

**Origin node** does not multiply anything — the front still renders one entry
per inbound. It says which of your servers the CDN forwards to, and the panel
uses it for exactly two things: leaving the front out of the file of a user who
is not provisioned on that node (where the link could not authenticate anyway),
and warning you when the node you named does not serve an inbound you enabled
the front on.

Leave it unset when your CDN decides, and neither check runs.

### Only through a front

An inbound's **Only through a front** switch drops its direct entries from a
subscription — the node's address then appears nowhere in that customer's file,
which is the point of fronting it in the first place.

It applies **per user, and only where a front actually rendered for them**. A
front tied to an origin node a particular customer cannot reach would otherwise
empty their file with nothing to say why. With no front enabled at all the
switch does nothing, and the direct entries keep rendering.

### What cannot be fronted, and what to do instead

The panel refuses these pairs when you save them, from either end, rather than
dropping the entry silently when the subscription is built. The reason is
always the same sentence: **a CDN terminates TLS and forwards HTTP.**

| Refused | Why |
| --- | --- |
| **REALITY** | it pins the handshake to the inbound's own key, and the CDN presents its own certificate. There is no configuration in which the two work |
| **Hysteria, Hysteria2, TUIC** | they run over QUIC, which is UDP. An HTTP/3 edge terminates the QUIC session itself and speaks its own protocol to the origin, so nothing of the proxy survives |
| **Port hopping** | the port set belongs to the node's own listener. A front is one hostname on one port |
| **Raw TCP, AnyTLS, ShadowTLS, SOCKS, SSH, mieru…** | a terminating CDN has no way to carry a stream that is not an HTTP request |

Carriable transports are **WebSocket, HTTPUpgrade, gRPC, XHTTP and HTTP/2**.

For everything on that list the answer is a **second address on the node**
rather than a front. A relay that forwards raw TCP without terminating anything
carries all of them fine — and to this panel that relay is another address in
the node's link-address list, not a CDN route.

An inbound the save would refuse is never offered in the front's inbound
picker, and the picker says why.

### If the inbound sits behind an ingress

An ingress routes by the name in the TLS handshake. A CDN opens its **own**
connection to the origin carrying the **front's** hostname, not the inbound's
own `server_name` — so an ingress route that does not list the front's hostname
sends that traffic to its fallback, which in the recommended layout is a
simulated web page. Nothing errors. The customer simply never arrives.

The panel warns rather than refusing, because the route and the front are
routinely written in either order. Add the front's hostname to the route (or a
`.cdn.example.com` suffix pattern, which also covers a wildcard front) and the
warning clears.

## Naming the entries

**Settings → Subscriptions → Link names.** Empty by default, and empty means
every entry keeps the name this panel has always produced. That default is
deliberate: clients key a user's saved selection on the entry name, so a
template is something to choose, not something to fill in.

A template is free text with `{VARIABLES}` in it:

```
{USER} · {ROUTE} · {REMAINING}        →   ali · CDN · 42.1 GB
{INBOUND}-{NODE}                      →   vless-ws-de-1
{USER_REMARK} {PROTOCOL} {DAYS_LEFT}d →   Ali VIP vless 17d
```

| Variable | |
| --- | --- |
| `{USER}` `{USER_REMARK}` | the account's name and its remark |
| `{INBOUND}` `{PROTOCOL}` `{NETWORK}` | the inbound's tag, its protocol, its transport |
| `{NODE}` `{NODE_REMARK}` | the node, for a direct entry. Empty on a front entry — a front is not on one node |
| `{ROUTE}` | how this entry reaches the fleet: the label of the node address, or the front's label |
| `{SERVER}` `{PORT}` | what the entry actually dials |
| `{USED}` `{REMAINING}` `{TOTAL}` | traffic, formatted; `∞` where there is no limit |
| `{DAYS_LEFT}` `{EXPIRE}` | days remaining, and the date; `∞` where there is no expiry |
| `{EXPIRE_JALALI}` | the same date in the Solar Hijri calendar |

Four rules, all of which the **Preview** under the field demonstrates on a
sample account — it is rendered by the panel's own renderer, not a guess, so
what you see is what your customers get:

- **Anything outside that list is left exactly as written.** `{SEVER}` renders
  as `{SEVER}`, so a typo is visible instead of quietly deleting part of every
  name. A template with no known variable in it at all is refused when you
  save, because every entry would come out with the same name.
- **An empty variable takes its separator with it.** `{USER}-{NODE}-{INBOUND}`
  on a front entry, which has no node, renders `ali-vless-ws` and not
  `ali--vless-ws`. A separator you wrote between two variables that both
  resolved is never touched.
- **Dates and quantities are the ones the subscription page shows**, in the
  panel's timezone, so a name and the page cannot disagree.
- Names are capped at 128 characters, and an entry whose template resolved to
  nothing falls back to the fixed name rather than arriving unnamed.

Downloadable app configs (`.ovpn`, `.conf`) keep their own naming. Those
strings are file names, and an `∞` or a `/` in a file name is a different kind
of problem.

## What the client is told

A subscription response carries more than the configs. Clients that know these
headers show a title, a quota bar, an announcement and a support button without
the user opening anything.

| Header | From | Read by |
| --- | --- | --- |
| `Profile-Title` | **Settings → Subscriptions → Profile title**, or the user's remark | Happ, v2RayTun (~25 characters in Happ) |
| `Subscription-Userinfo` | the account's quota, usage and expiry | Happ, v2RayTun, Clash Meta |
| `Profile-Update-Interval` | **Client refresh interval** | Happ, v2RayTun. Clash Meta for Android ignores it |
| `Announce` | **Announcement** | Happ (~200 characters), v2RayTun |
| `Support-Url` | **Support link** | Happ |
| `Profile-Web-Page-Url` | **Offer a link back to the subscription page** | Happ |

All six are in the XTLS subscription standard, which is where the spellings
come from. Only names with a client that documents reading them are sent. A header nobody
reads is dead weight, and one spelled differently from the rest of the
ecosystem is worse, because it looks implemented.

Two settings on that page decide the shape of the response rather than its
content:

- **Client refresh interval** — hours; empty means 12. Set it to `0` and the
  header is not sent at all, leaving every client on its own default.
- **Offer a link back to the subscription page** — off **removes** the header
  rather than sending an empty one, because an empty value is a button that
  opens nothing.

Non-ASCII text — a Persian title, a Russian announcement — goes out
base64-encoded behind a `base64:` prefix, which is what clients in this
ecosystem implement. Newlines in an announcement become spaces: an HTTP header
is one line.

## Tell your users to turn Mux off

Xray-based clients — **v2rayNG, v2rayN, Streisand** — have a **Mux** switch.
Turning it on makes the client speak `mux.cool`, a multiplexing protocol these
servers do not implement and will not: Nexora's nodes run sing-box, whose
multiplexing is a different protocol entirely.

With Mux on, the connection fails. Not with an error the user can act on —
it simply does not work, which arrives in your support chat as "the configs are
broken".

There is nothing the panel can do from its side: it cannot stop a client
framing its own traffic. So the subscription page carries the warning itself,
in the customer's own language, under **Advanced** — and it is worth repeating
wherever you write your own setup instructions.

The multiplexing setting in sing-box and Clash apps is a different feature
entirely and is fine left alone — the warning is about the Xray one.

## When a client imports the link and shows nothing

v2rayNG keeps each subscription in its own group, and **Update subscription
refreshes the group that is currently selected** — not every group the app
holds. A customer who imports your link and then updates while a different
group is on screen gets an empty list and **no error at all**: the subscription
is stored, its URL is right, the toggle is on, and nothing says why there is
nothing in it.

They have to select the new group's tab first, then update. Put it in your own
setup instructions for Xray-based clients: the symptom is indistinguishable
from a subscription link that does not work, so it arrives in your support chat
as one.
