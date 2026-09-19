# Monitoring

The panel publishes its own figures at `/metrics` in the Prometheus format, and
this repository ships a Prometheus scrape config, a Grafana dashboard and a
compose overlay that runs both beside your panel.

| | |
| --- | --- |
| [Quick start with Docker](#quick-start-with-docker) | both services beside an existing stack |
| [The token](#the-token) | why the endpoint is not open, and how to mint one |
| [Without Docker](#without-docker) | an existing Prometheus and Grafana |
| [What is exported](#what-is-exported) | the metric names, and what each one means |
| [Two rules worth knowing](#two-rules-worth-knowing) | why a series can be missing, and why nothing is per user |
| [Alerts worth having](#alerts-worth-having) | four rules that earn their keep |

## Quick start with Docker

This is an **overlay**: it adds Prometheus and Grafana to the compose file you
already run, so they join the panel's network and reach it by service name. The
panel needs no extra published port.

```bash
# 1. Copy the monitoring directory next to your docker-compose.yml
curl -fsSL https://github.com/nexora-vpn/panel/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 panel-main/monitoring

# 2. Mint a token in the panel (below) and put it in the file Prometheus reads
printf '%s' 'PASTE-THE-TOKEN' > monitoring/prometheus/token

# 3. Set Grafana's password
cp monitoring/.env.example .env      # or merge those lines into your existing .env
${EDITOR:-nano} .env

# 4. Start everything
docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
```

**Keep using both `-f` files from then on.** Compose treats the files it is given
as the whole description of the project, so a later plain `docker compose up -d`
would remove the two services again. If that is easy to forget, set it once:

```bash
echo 'COMPOSE_FILE=docker-compose.yml:monitoring/docker-compose.monitoring.yml' >> .env
```

Then reach Grafana. It is published on loopback only, because it is one more
login and it is not the one you are selling:

```bash
ssh -L 3000:localhost:3000 you@your-server
# then open http://localhost:3000 and sign in with GRAFANA_PASSWORD
```

The **Nexora fleet** dashboard is already there, in a folder called Nexora, with
its datasource wired up. Nothing to import.

Prometheus is deliberately **not** published at all. It has no authentication of
its own and it holds your whole operational picture; publishing it would undo
the reason `/metrics` needs a token in the first place. Grafana reaches it inside
the compose network.

### If your panel terminates TLS

The scrape hop never leaves the Docker network, but if the panel is serving
HTTPS itself (Settings → Web, mode `self_signed` or `files`) Prometheus has to
speak HTTPS to it. Edit `monitoring/prometheus/prometheus.yml`:

```yaml
    scheme: https
    tls_config:
      insecure_skip_verify: true
```

Skipping verification is correct here and not a shortcut: the panel's
certificate is issued for the hostname your customers use, not for the `panel`
service name Prometheus dials, so a strict check would reject a certificate that
is perfectly valid.

### If your panel is on a base path

`/metrics` moved with it. Set `metrics_path: /your-base-path/metrics`.

## The token

`/metrics` is authenticated like every other route, and there is no
unauthenticated mode. The document names every node you run and the address of
each one — an endpoint that hands that out cannot be un-shipped once installs
are using it.

In the panel: **Admins → API tokens → add**, scope **`stats:read`** and nothing
else. That scope reaches the observability surface and no data you would mind a
scraper holding.

Put the token in `monitoring/prometheus/token`, a file of its own rather than a
value inside `prometheus.yml`, because a config file gets pasted into issues and
chat messages and a credential should not travel with it. The repository's
`.gitignore` already excludes it.

Revoking the token in the panel stops the scrape immediately; nothing is cached.

## Without Docker

Any Prometheus can scrape it. The minimum:

```yaml
scrape_configs:
  - job_name: nexora-panel
    scheme: https
    metrics_path: /metrics
    authorization:
      type: Bearer
      credentials_file: /etc/prometheus/nexora-token
    static_configs:
      - targets: ['panel.example.com']
```

A 60-second interval is plenty: the host figures behind the disk and memory
series are sampled every five minutes, and the traffic counters are cumulative,
so nothing is lost between scrapes.

For Grafana, import `monitoring/grafana/dashboards/nexora-fleet.json`. It
references a Prometheus datasource with the uid `nexora-prometheus`; either give
your datasource that uid, or find-and-replace it in the JSON once.

## What is exported

Everything below is per node, per fixed category, or fleet-wide.

**The panel**

| Metric | Meaning |
| --- | --- |
| `nexora_panel_build_info` | 1, with the running version as a label |
| `nexora_panel_start_time_seconds` | when the current panel process bound its listener; `time() - this` is its uptime |

**The licence**

| Metric | Meaning |
| --- | --- |
| `nexora_license_valid` | 1 when the licence checks out, 0 on the free tier or any invalid state |
| `nexora_license_expires_at_seconds` | expiry. Absent when the licence does not expire |
| `nexora_license_limit{resource}` | the cap for each resource; 0 means unlimited |
| `nexora_license_used{resource}` | rows counted against that cap |

**Accounts**

| Metric | Meaning |
| --- | --- |
| `nexora_users_total{status}` | accounts by status: active, disabled, expired, limited, pending |
| `nexora_users_online` | accounts with traffic inside the online window |

**Nodes** — every one of these carries `node` (the name) and `id`.

| Metric | Meaning |
| --- | --- |
| `nexora_nodes_total` | how many nodes the panel knows about |
| `nexora_node_up` | 1 when the last heartbeat connected |
| `nexora_node_enabled` | 1 when you have the node switched on |
| `nexora_node_traffic_bytes_total{direction}` | traffic accounted to the node since it was added |
| `nexora_node_online_users` | distinct accounts with traffic on that node in the online window |
| `nexora_node_connections` | connections the node's engine holds open |
| `nexora_node_engine_restarts_total` | engine restarts since the node agent started |
| `nexora_node_disk_bytes`, `nexora_node_disk_used_bytes` | the root filesystem |
| `nexora_node_memory_bytes`, `nexora_node_memory_used_bytes` | host RAM |
| `nexora_node_load1` | one-minute load average |

**The event bus** — the one failure in the panel that is otherwise silent,
because a delivery that never lands reports itself to nobody.

| Metric | Meaning |
| --- | --- |
| `nexora_event_deliveries{status}` | deliveries by status: pending, delivered, dead |
| `nexora_event_subscribers` | how many subscribers are enabled |

## Two rules worth knowing

**A figure a node did not report has no series at all.** Disk, memory, load,
connections, engine restarts and the per-node online count are all conditional:
a node running an older agent, or a platform without `/proc`, reports nothing for
them, and the panel exports nothing rather than a zero. A zero would draw a graph
in which the disk emptied itself and everyone went offline. So **a gap in one of
those graphs means the panel does not know**, not that the number fell — which
is also how the panel's own node uptime bar draws it.

The one exception is `nexora_event_deliveries`, which always reports every
status. An alert on dead deliveries has to be able to evaluate on a healthy panel
or it will never fire on an unhealthy one.

**Nothing is labelled per account.** One label per user would be one time series
per user, kept for as long as your retention — ten thousand customers is ten
thousand series that never retire, and it is the usual way a monitoring stack
becomes the thing that falls over. Per-account questions are answered on demand
by the panel's own **Reports** page, which can be asked about a period instead of
being scraped for ever.

## Alerts worth having

Four that are worth the noise. Adapt the thresholds to your fleet.

```yaml
groups:
  - name: nexora
    rules:
      # The panel stopped answering. Everything else is downstream of this, so
      # keep the window short enough to beat a restart and long enough not to
      # fire on one.
      - alert: NexoraPanelDown
        expr: up{job="nexora-panel"} == 0
        for: 5m

      # A node your panel believes should be serving is not answering. The
      # `enabled` half matters: a node you switched off is not an outage.
      - alert: NexoraNodeDown
        expr: nexora_node_up == 0 and nexora_node_enabled == 1
        for: 10m

      # A disk that fills stops the node without warning. The panel raises its
      # own node.disk_high event at 90% too; this is the copy that reaches you
      # even if you have no notification addon installed.
      - alert: NexoraNodeDiskFilling
        expr: nexora_node_disk_used_bytes / nexora_node_disk_bytes > 0.9
        for: 30m

      # Deliveries that have given up. Nothing else reports this: a webhook that
      # never lands tells its receiver nothing by construction.
      - alert: NexoraEventDeliveriesDead
        expr: increase(nexora_event_deliveries{status="dead"}[1h]) > 0
```

An alert on the licence is worth adding if you sell on one:
`nexora_license_valid == 0`, or
`nexora_license_expires_at_seconds - time() < 7 * 86400`. There is no grace
period after the date, so the notice is the whole mitigation.
