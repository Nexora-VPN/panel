# Tunnels

A tunnel links two of your nodes: users connect to one of them, the **relay**,
and their traffic leaves for the internet from another, the **origin**. What it
is for:

- **A good entry, a different exit.** Users reach a server their network gets to
  easily — close to them, on a well-routed datacentre, on an address that is not
  filtered — while their traffic comes out of a server somewhere else.
- **An exit that accepts no connections.** In the default arrangement the origin
  dials out to the relay, so it works behind NAT or with every incoming port
  closed, and users never face it.
- **Several exits behind one entry.** One relay can carry a tunnel to several
  origins.

**Tunnels** in the sidebar, directly under **Nodes**.

| | |
| --- | --- |
| [How a tunnel works](#how-a-tunnel-works) | relay, origins, and what a user sticks to |
| [Before you start](#before-you-start) | nodes, addresses and the port |
| [Reverse or direct](#reverse-or-direct) | which side opens the port |
| [Creating a tunnel](#creating-a-tunnel) | the form, field by field |
| [Security and transport](#security-and-transport) | REALITY, TLS, none; WebSocket, gRPC, QUIC… |
| [Profiles](#profiles) | several ways onto one tunnel |
| [Where the relay's traffic goes](#where-the-relays-traffic-goes) | the default exit, and routing only some traffic |
| [Health and live status](#health-and-live-status) | the list, the status dialog, *Reset* |
| [A tunnel per relay](#a-tunnel-per-relay) | *Duplicate* and editing several at once |
| [When it does not connect](#when-it-does-not-connect) | what to check |

## How a tunnel works

- **The relay** is where users connect, through the ordinary inbounds of its
  template — nothing about the users or their links changes. What the relay
  would have sent to the internet goes down the tunnel instead.
- **The origins** are where that traffic leaves for the internet. On the origin
  it goes through the origin's own routing, like any traffic arriving there.
- **A user sticks to one origin** for as long as that origin is connected, so
  their exit address does not change from one connection to the next — which is
  what keeps sites from logging them out or asking for a CAPTCHA every time.
  When an origin is lost, only the users who were on it move to another.
- **TCP and UDP** both go through.
- **A tunnel touches nothing else.** It has its own port and its own
  credentials, one per origin, that the panel derives and never stores — nothing
  to copy, nothing that can fall out of step between the two ends. No inbound is
  used, no account is created for it, and users' traffic is still counted where
  they connect, on the relay.
- **Changes reach the nodes live.** Creating, editing, disabling or deleting a
  tunnel does not restart either node's core.

A node can be the relay of one tunnel and an origin of another, so a chain of
relays is possible. A node cannot be the relay and an origin of the *same*
tunnel.

## Before you start

1. **Both nodes are added and connected** on the **Nodes** page.
2. **The relay serves users**: it is on a template with inbounds, and the users
   are on that template. A tunnel only changes where the relay's traffic leaves;
   it does not make a node serve anyone.
3. **The listening node has an address the other can reach.** The dialing side
   dials the listening node's **Link addresses** (Nodes → edit), every one of
   them at once as failover, or its **Address** when it has none. The panel
   refuses to save a tunnel whose listening node has neither.
4. **The port is free and open.** Each tunnel binds a port of its own on the
   listening node (default `8443`). The panel refuses one that an inbound or
   another tunnel already uses there. If that server has a firewall, open the
   port in it — the panel does not.
5. **Update the panel before its nodes**, as for every release. A tunnel with
   more than one [profile](#profiles) needs a current node; an older node reads
   only one.

## Reverse or direct

The mode decides only which side opens the port. Traffic flows the same way in
both: users → relay → origin → internet.

| | Reverse (default) | Direct |
| --- | --- | --- |
| Who listens | the relay | each origin |
| Who dials | each origin dials the relay | the relay dials each origin |
| The port must be open on | the relay | every origin |
| Origin behind NAT or fully firewalled | works | does not work |
| Choose it when | almost always | the relay cannot accept connections from the origins, but can dial out to them |

The form says in one sentence what the tunnel will do, with your node names —
for example *"relay-1 listens on port 8443 for exit-de, exit-nl to dial in.
Traffic leaves the internet from them."*

## Creating a tunnel

**Tunnels → Add tunnel.**

| Field | |
| --- | --- |
| Name | becomes the tunnel's **tag**, `tunnel-` plus the name in lowercase Latin letters and digits (spaces, dots and underscores become `-`; other characters are dropped). A name with no Latin letters or digits gets `tunnel-t<id>`. At most 48 characters, and **it cannot be changed after saving** — the tag and both ends' credentials are built from it. Two names that give the same tag (`eu west` and `eu-west`) are refused. |
| Mode | [Reverse or Direct](#reverse-or-direct) |
| Relay node | where users connect |
| Origin nodes | one or more; where traffic leaves for the internet |
| Links per origin | how many parallel connections each origin keeps, default 4, at most 64. Each has its own congestion window, so one lost packet stalls only the streams on that connection. Four is right for almost every path. |
| Stream window | how much one connection may have in flight; empty = 4 MiB, otherwise between 256 KiB and 1 GiB. Raise it only when a single download is slow over a long path while several together are fast. |
| Enabled | a disabled tunnel is removed from both nodes and keeps its settings |

Below that is the tunnel's first **profile**: its **Listen port**, and the
**Security**, **Transport** and **Advanced** tabs. A new tunnel starts on
REALITY with nothing to fill in; **Save** and it is on both nodes.

## Security and transport

**Security** — what protects the link between the two nodes:

- **REALITY** (the default) makes the link look like an ordinary TLS connection
  to a well-known site and needs no certificate. The private key and short IDs
  are generated when you save; the handshake site can be changed.
- **TLS** — the panel issues a certificate for the tunnel's own name
  (`<name>.tunnel.internal`, a name that resolves nowhere; the connection still
  goes to the node's address) and the other side pins that exact certificate.
  Nothing to buy, and nothing to renew: it lasts ten years. To use your own,
  paste both the certificate and the key as PEM; half a pair, or a file path on
  the node, is refused.
- **None** — the link is plaintext. The token still keeps strangers out, but
  everything your users send crosses between the two nodes in the clear.

**Transport** — optionally wraps the link so it reads as a web request rather
than one unrecognisable long-lived stream: **WebSocket**, **gRPC**, **HTTP**,
**HTTPUpgrade**, or **QUIC**. QUIC carries its own TLS, so it needs **TLS** on
the Security tab and cannot run with REALITY; the form and the panel both refuse
those pairs.

**Advanced** shows the TLS and transport blocks exactly as the node receives
them. Editing there overrides the tabs.

## Profiles

A profile is one way the tunnel is carried: its own port, its own security and
its own transport. *Add a way to carry this tunnel* (the **+** beside the
profile chips) adds another, up to eight. They are not separate tunnels: their
connections share one pool under the same origins, so **a protocol that gets
blocked costs throughput, not the tunnel** — and not a user's exit address,
which stays with the origin whatever profile carried them.

A typical pair: REALITY on one port, and WebSocket over TLS on another.

With two or more profiles two more settings appear:

- **Load balancing** — **Spread**: every profile that is connected carries
  traffic, and a new connection takes the least busy one. **Priority**: the
  first profile in the list that is connected carries everything; the next is
  used only when it has none — a fallback rather than extra capacity.
- **Links for this profile** — the profile's share of the load. Connections
  spread over links, so a profile with six links against one with two takes
  three times the traffic. Empty takes *Links per origin*.

Each profile needs a port of its own, different from the others, from every
inbound on the listening node and from every other tunnel there.

## Where the relay's traffic goes

**When the relay relays exactly one tunnel, it becomes the relay's default
exit** — the panel sets that node's *final* outbound to the tunnel's tag by
itself. The **Default exit** column on the list says whether it is. Rules in
the template's route still come first on the relay, so a rule that sends some
traffic `direct` or blocks it still does so there.

**Never write a tunnel's tag into a template's route.** Only the relay has that
tag; every other node on the template would be handed a route naming an
outbound it does not have, and its core would refuse to start.

The panel does not choose an exit, and says why in the Default exit column,
when:

- **the relay relays more than one tunnel** — which traffic goes down which is
  your choice;
- **the relay has its own final** — a node's own route always wins.

In both cases, and whenever only *some* traffic should use the tunnel, write it
in the relay's own route: **Nodes → Config → Routing (per-node override)**.
Rules there are added after the template's and may name tunnel tags, because
they reach the relay alone. For example, a relay carrying two tunnels:

```json
{
  "rules": [
    { "rule_set": ["geosite-netflix"], "outbound": "tunnel-exit-us" }
  ],
  "final": "tunnel-exit-de"
}
```

A rule set named there must be one the relay's template carries. **Route
test** on the node's menu shows which rule a given address would match and where it
would go.

## Health and live status

**The list** asks both ends of every tunnel after it opens — a tunnel's health
cannot be read from its settings:

| Health | Meaning |
| --- | --- |
| *n* links | working; *n* connections are up |
| No links attached | the relay answers, but no origin is connected to it — see [below](#when-it-does-not-connect) |
| Relay unreachable | the panel cannot reach the relay node |
| Unknown | the check failed; it is not a statement about the tunnel |

The strip above the list counts the same states; click one to show only those.
*Refresh health* asks again.

**Live status** on a row's menu asks every node of the tunnel and refreshes
itself every few seconds while it is open: per origin, its links and streams
and how long they have been up, and on the dialing side the connections
wanted, the time until the next try (*Backoff*) and the **Last error**.

**Reset** in that dialog rebuilds the tunnel on every node: every connection is
dropped and the dialing side starts again at once. Use it when a side is up but
carries nothing, or when a dialer is waiting the full minute between tries
after a block that has since been lifted. Traffic on the tunnel stops until it
reconnects.

**Usage graph** on the row's menu shows the traffic that went through the
tunnel.

## A tunnel per relay

Several relays reaching the same origins are **one tunnel per relay**, not one
tunnel with several relays. That way a credential taken off one relay opens
nothing on another, and adding a relay is a new tunnel rather than an edit to
the ones carrying traffic.

- **Duplicate** on a row's menu asks for a name and the relay, and copies the
  origins, profiles and settings. The certificate and keys are *not* copied:
  the copy gets its own.
- **Selecting rows** gives *Edit selected…* — set the origins, links per origin,
  stream window or load balancing on all of them at once; an empty field is left
  as it is — and *Enable*, *Disable*, *Reset* and *Delete*.

Deleting a node removes it from every tunnel it was in. A tunnel left without
its relay or without any origin is deleted with it, and the audit log records
that.

## When it does not connect

Open **Live status** and read **Last error** first. Then:

- **Firewall** — the listen port open on the listening node: the relay in
  *Reverse*, every origin in *Direct*. Check from the other node:
  `nc -vz <address> <port>`.
- **The address** — the dialing side uses the listening node's Link addresses,
  or its Address when there are none. An address only the panel can reach (a
  private or management address) is no use to the other node; put the public
  one under Link addresses.
- **A CDN address among the Link addresses** is dialed too. If the tunnel
  cannot pass through that CDN, that address just stays in backoff while the
  others carry the tunnel.
- **The handshake site** of REALITY must be reachable from the listening node
  and serve TLS 1.3.
- **After unblocking something**, press *Reset* rather than waiting for the
  next try.
- **Mode** — an origin behind NAT works only in *Reverse*.
