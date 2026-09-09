# Choosing a database

Nexora runs on SQLite or PostgreSQL. The installer asks for neither — it takes
SQLite unless you pass `--postgres` — because for most panels the choice does not
matter, and for the ones where it does, the deciding number is one you already
know: how many of your users are *passing traffic at the same time*.

This page is the recommendation, why it is what it is, and what to do when you
outgrow it.

## The short version

| Situation | Database |
| --- | --- |
| Up to ~10,000 concurrently active users | **SQLite** |
| Above ~25,000 concurrently active users, or above ~10,000 on a slow disk | **PostgreSQL** |
| The database file would live on NFS, a network volume, or any shared storage | **PostgreSQL**, at any size |
| More than one panel process against one database | **PostgreSQL**, at any size |
| You already run a PostgreSQL server | **PostgreSQL** — the marginal cost is zero |

"Concurrently active" means users the nodes report traffic for in the same
30-second collection, not users in your database. A panel with 50,000 accounts of
which 3,000 are online at peak is a 3,000-user panel for this purpose.

The number of **nodes** barely matters. A user passes traffic through one node at
a time, so ten nodes serving 10,000 users between them cost about what one node
serving 10,000 users costs; each extra node adds only its own handful of
per-inbound counters.

Between the two thresholds, either works. Prefer SQLite if you value having one
file to copy; prefer PostgreSQL if you would rather not revisit the decision.

## Why the numbers are what they are

Everything the panel does to the database is small and constant — an operator
loading a page, a client fetching a subscription — except one thing. Every 30
seconds the panel drains each node's traffic counters and writes them: per-user
totals, per-node rollups, and the samples behind the usage graphs. That burst is
proportional to the number of active users, and it is one transaction.

Here is what it costs, measured — one drain, written to a file-backed SQLite
database tuned the way the panel tunes it, on an NVMe disk:

| Concurrently active users | Time to write one drain |
| --- | --- |
| 100 | 3 ms |
| 1,000 | 39 ms |
| 5,000 | 153 ms |
| 10,000 | 319 ms |

Against a 30-second cycle, even the last row occupies the write path about 1% of
the time. That is why the threshold above is where it is and not lower — and why
the second column is the number to check on *your* hardware rather than trusting
this table, since a cheap VPS disk can be several times slower than the one this
was measured on. From a source checkout:

```sh
go test ./internal/service/ -run '^$' -bench BenchmarkAccount -benchtime 10x
```

SQLite allows exactly one writer at a time, over the whole file. While a burst is
being written, every other write waits. Nexora configures SQLite so that they
*wait* rather than fail (see below), which is the difference between a slow
minute and an error — but waiting is still waiting, and past some size the next
burst arrives before the last one finished.

PostgreSQL writes rows, not files: the accounting burst and everything else
proceed at the same time, and readers are never blocked by a writer at all. That
is the whole of the difference. It is not that PostgreSQL is faster — for a small
panel it is measurably slower, because every statement is a round trip over a
socket instead of a function call inside the panel's own process.

So: SQLite is faster until it is contended, and PostgreSQL does not care that it
is contended. Pick by contention, not by size.

## What is not a reason to switch

- **Number of accounts.** A hundred thousand rows is nothing to SQLite. What
  costs is traffic being written for them, and dormant accounts write nothing.
- **Number of subscriptions served.** Those are reads, and under WAL (which the
  panel enables) readers are never blocked.
- **Reliability worries in the abstract.** SQLite does not lose a database to a
  crash or a power cut; it is one of the most heavily tested pieces of software
  in existence. It loses to *shared storage* and to *two processes*, which is why
  those two rows above say PostgreSQL at any size.

## What the panel tunes for you

Neither backend is left on its defaults, and you do not have to configure either.
Whichever the installer put in `config.json`, the panel applies on every start:

**SQLite**

| Setting | Value | Why |
| --- | --- | --- |
| `journal_mode` | WAL | The default blocks every reader for the whole of every write. WAL lets readers work from the last committed snapshot while a write is in flight. |
| `synchronous` | NORMAL | The documented safe pairing with WAL: a crash cannot corrupt the database, only lose the last transactions. FULL means an fsync per commit, which is what makes a cheap disk feel broken. |
| `busy_timeout` | 10s | A contended writer waits instead of returning "database is locked". |
| `cache_size` | 8 MiB per connection | Enough to hold the users table for the checks that run every minute. |
| `_txlock` | immediate | The subtle one. A transaction that reads and then writes cannot wait for the lock — promoting a read lock while another writer holds one is a deadlock, not a wait, and fails instantly no matter how long the timeout is. Taking the write lock up front turns it into an ordinary wait. |
| Pool | 8 connections | Readers benefit from more than one; writers serialise regardless. |

**PostgreSQL**

| Setting | Value | Why |
| --- | --- | --- |
| Pool | 20 connections, 5 idle | Leaves room for other users of the server: `max_connections` defaults to 100 and is shared with everything else on the host. |
| Connection lifetime | 30 minutes | A long-lived panel does not pin server-side memory, or a connection to an instance that has since been failed over, for its entire uptime. |

The pool size is the one figure worth overriding, and only on a PostgreSQL server
you share with other applications. Set `max_open_conns` in `config.json`:

```json
{ "db": { "driver": "postgres", "dsn": "…", "max_open_conns": 10 } }
```

or `NEXORA_DB_MAX_OPEN_CONNS=10` in the environment. Leave it out otherwise.

Any pragma you spell out yourself in a SQLite DSN is left alone — the panel adds
to your DSN, it does not argue with it.

## Switching later

You are not locked in. A Nexora backup is a logical dump, one file per table, not
a copy of a database file — so an archive taken on one backend restores onto the
other, and that is the supported migration path in both directions:

1. On the old panel: **Backup → Create**, and download the archive.
2. Install or reconfigure the panel against the new database (`config.json`'s
   `driver` and `dsn`, or a fresh install with `--postgres`).
3. On the new, empty panel: restore the archive — from the setup wizard if it has
   not been configured yet, or from **Backup → Restore** if it has.

The restore rewrites every admin account, so log in with the credentials from the
old panel afterwards. Your licence and this host's own address settings are kept
rather than taken from the archive, since both are specific to the machine.

Two things live outside the database and outside the archive, and have to be moved
by hand if you are also changing hosts: the subscription themes in the theme
directory, and the staged node binaries. Nodes themselves need nothing — they hold
no state.

## Where the database lives

With SQLite it is a single file, `/var/opt/nexora/nexora.db` by default, with
`-wal` and `-shm` files beside it while the panel is running. **Copying those
three files while the panel runs is not a backup** — use the panel's own backup,
which takes a consistent snapshot without stopping anything.

With PostgreSQL the panel holds a connection string and nothing else; back it up
however you back up that server, or with the panel's backup, which works the same
on both.
