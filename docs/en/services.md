# Panel services

The **Services** menu in the sidebar (main admin only) holds what the panel
talks to outside itself: notices in Telegram and by email, copies of every
backup somewhere else, and signing in with an account you already have at
Google, Microsoft, GitHub or your own identity server. Webhooks live there too.

| | |
| --- | --- |
| [Off until you switch it on](#off-until-you-switch-it-on) | what every service has in common |
| [Telegram](#telegram) | notices in a chat, and a few read-only commands |
| [Email](#email) | the same notices by mail |
| [Backup destinations](#backup-destinations) | S3-compatible storage, SFTP, a Telegram chat |
| [Single sign-on](#single-sign-on) | a login button per provider |

## Off until you switch it on

Every service starts off, and a service that is off runs nothing and opens no
connection. Each one is a card with the same parts:

- **Service on** — the switch.
- **Its settings.** A password, token or key is never shown again once saved:
  the box says *Set — leave empty to keep*. An empty box keeps what is stored.
- **Test** — tries what is *saved*, so save first.
- **Last run** — when the service last did something, and the last error if
  that failed.

A service's settings are stored in the database like every other credential the
panel holds, which means they are in every backup — another reason to set a
backup passphrase.

## Telegram

**Services → Telegram.** The panel sends its notices — a customer about to
expire or run out of traffic, a node going down, a backup that failed — to
Telegram chats, each paired to one panel account. A chat hears only what its
account may see: **a reseller's chat hears about its own customers and nothing
else.**

**1. Make a bot.** In Telegram, talk to **@BotFather**, send `/newbot`, and
copy the token it gives you into **Bot token**. Use a bot of its own for the
panel: while a chat is being paired the panel reads the bot's messages, and
another program reading the same bot would take them first.

**2. If the panel runs in Iran,** `api.telegram.org` is not reachable from
there. Fill in one of:

- **Proxy** — `socks5://host:port` or `http://host:port` (a username and
  password go in the address: `socks5://user:pass@host:port`).
- **Bot API address** — a [Bot API server](https://github.com/tdlib/telegram-bot-api)
  you run outside, instead of a proxy.

Switch the service on, save, and press **Test**.

**3. Pair a chat.** *Pair a chat*, choose the account, the language of its
notices and the events it should hear, then *Get a code*. The dialog shows:

- a link and a QR code — open it on the phone that should get the notices and
  press **Start**;
- the code itself, to send to the bot by hand;
- for a **group**: *Add the bot to a group*, which lets you pick the group and
  sends the code there, or the line `/start@yourbot CODE` to send in a group
  the bot is already in. In a group the bot hears only commands addressed to it
  by name, so a bare code sent there is not seen.

The code is good for ten minutes. Every account can also pair its own chat
from its menu (**My Telegram**) — a reseller does not need the main admin for
it.

**Events.** *Everything this account may read* includes events a later release
adds. Untick it to choose; an event the account cannot see is greyed out and
never reaches its chat. A chat that cannot be reached is retried the way a
webhook is, so notices sent while Telegram or the proxy was down arrive when it
is back.

**Deliveries** on a chat's row lists every notice sent to it — delivered, waiting
for another try, or given up — with Telegram's answer, and *Send again* on any
of them. Every account sees its own chats' from **My Telegram**.

**Commands.** In a paired chat:

| Command | Answers |
| --- | --- |
| `/status` | a summary: accounts by status and online now — a reseller only its own — and, for the main admin and operators, the nodes |
| `/user name` | one account: traffic, expiry, online — a reseller only its own |
| `/node name` | one node (main admin and operators) |

In a group, add the bot's name: `/user@yourbot name`. The commands only read;
nothing in the chat can change the panel.

## Email

**Services → Email.** The same notices, by mail.

| Setting | |
| --- | --- |
| SMTP server | the mail server's name, e.g. `smtp.gmail.com` — no scheme, no port |
| Port | empty = 587 for STARTTLS, 465 for TLS, 25 for none |
| Security | **STARTTLS** upgrades a plain connection (usually 587); **TLS** is encrypted from the first byte (usually 465); **None** sends everything, the login included, unencrypted — only for a relay on this server or a private network |
| Certificate | **Do not verify** only for your own server with a self-signed certificate |
| Username, Password | empty username = no login |
| Sender | `Nexora <panel@example.com>`; most servers send only from an address you own |

**Gmail** and most large providers refuse your ordinary password over SMTP
(`534 Application-specific password required`): turn on two-step verification
for the account and use an **App Password** instead.

**Adding an address.** *Add an address* mails a six-digit code to it; typing the
code back adds it. Nothing is ever sent to an address that has not been
confirmed — a typo cannot send your customers' names to a stranger. The code is
good for ten minutes and five tries. Every account can add its own from its
menu (**My email**), and a reseller's address hears about its own customers
only. **Deliveries** on an address's row shows what was mailed to it, as for a
chat.

## Backup destinations

**Services → Backup destinations.** Every archive the panel writes — scheduled
or taken by hand under **Settings → Backup** — is also sent to each destination
that is on, in the background.

**A failed upload never fails the backup.** The archive stays on this server,
the destination shows the error, the event `panel.backup_upload_failed` goes
out (to Telegram and email too, if they listen for it), and the next archive is
sent again.

**Set a passphrase first** (Settings → Backup). An archive holds every
credential this panel has; unencrypted, whoever can read the destination has
them all. The page warns while there is none.

### S3-compatible storage

Cloudflare R2, AWS S3, Backblaze B2, MinIO, Iranian object storage — anything
that speaks S3.

| Setting | |
| --- | --- |
| Endpoint | the storage's address without the bucket: `https://<account>.r2.cloudflarestorage.com`, `https://s3.<region>.amazonaws.com`, `https://s3.<region>.backblazeb2.com`, your MinIO |
| Region | empty = `us-east-1`, which R2 and MinIO accept; AWS needs the bucket's own region |
| Bucket | must already exist |
| Access key, Secret key | a key that may write, list and delete in that bucket |
| Folder | a folder inside the bucket; empty = its root |
| Keep | how many archives to keep there; empty = the Backup page's retention, `0` = keep all |

### SFTP

Any server you reach over SSH.

| Setting | |
| --- | --- |
| Host, Port | no scheme; empty port = 22 |
| Username | |
| Password, Private key | either or both; the key in PEM or OpenSSH form, without a passphrase |
| Host key | filled in on the first connection and checked on every one after it — clear it only if that server was rebuilt |
| Directory | created if missing; empty = the login's home directory |
| Keep | as for S3 |

The archive is written under a temporary name and renamed when it is complete,
so a half-uploaded file never looks like a backup.

### Telegram

The archive as a file in a chat, sent by the bot saved on the Telegram service
and through its proxy. **Chat id** is a chat paired to a main-admin account — the
number the Telegram page shows under it. The Bot API takes files up to **50 MB**;
a larger archive is refused with that reason rather than sent to fail. Nothing
in the chat is ever deleted.

**Retention.** Only files named like the panel's archives are ever deleted from
a destination, so the same bucket or directory can hold other things.

## Single sign-on

**Services → Single sign-on.** A **Sign in with …** button on the login page for
each provider you add. Two rules hold whatever the provider:

- **No account is created from it.** Each account links its own identity: it
  logs in with its password, opens **Single sign-on** on its menu and presses
  *Link with …*. Someone with an account at the provider and no link here is
  refused.
- **Two-factor authentication still applies.** An account with a code is asked
  for it after the provider, as after a password.

**The redirect URI.** The page shows one address to register at every
provider, ending in `/api/login/oidc/callback`. It is the address the page is
open on, so open the panel at the address your operators use before you copy
it.

**Adding a provider.** *Add provider*, pick it at the top, and the form asks for
exactly what that provider needs, with where to create the client written above
the fields:

| Provider | You fill in |
| --- | --- |
| Google | Client ID, Client secret |
| Microsoft | Tenant (empty = `common`, any Microsoft account), Client ID, Client secret |
| GitHub | Client ID, Client secret |
| GitLab | Address (empty = gitlab.com), Client ID, Client secret |
| Keycloak | Address, Realm, Client ID, Client secret |
| Authentik | Address, Application slug, Client ID, Client secret |
| Okta | Domain, Authorization server (empty = `default`), Client ID, Client secret |
| Auth0 | Domain, Client ID, Client secret |
| OpenID Connect (other) | Issuer, Client ID, Client secret, Scopes — PocketID, Authelia, Zitadel, Kanidm, Dex and the like |
| OAuth 2.0 (other) | the authorization, token and user addresses, Client ID, Client secret, and which fields of the user answer are the id and the name |

*Test* checks that the provider answers. *Button name* changes what the button
says; *On the login page* takes it off without deleting it. Deleting a provider
removes the identities linked through it.

**Locked out?** `nexora-panel admin reset-password` also removes the account's
single sign-on links and turns its two-factor authentication off, so the
recovery command stays the one way back in — see
[locked out](install.md#locked-out).
