# The licence

What a licence changes, how to buy, renew or upgrade one without pasting a
key, how to take it to a new server, and what the panel needs from your
network to keep it.

| | |
| --- | --- |
| [What it caps](#what-it-caps) | users and nodes, and nothing else |
| [Buying one](#buying-one) | from the panel's own **License** page |
| [Renewing and upgrading](#renewing-and-upgrading) | the same button, and what each costs |
| [Moving to a new server](#moving-to-a-new-server) | a restored backup gets its licence back |
| [Staying in contact](#staying-in-contact) | the check-in every six hours, and the 14-day limit |
| [Questions and refunds](#questions-and-refunds) | there is no refund button |

## What it caps

A licence caps two things: **users** and **nodes**. Inbounds, outbounds,
endpoints and every feature are the same on every install, licensed or not.

Without a licence the panel runs on the **free tier: 25 users and 1 node**.
Past a cap nothing is deleted: the rows beyond it are listed, marked and still
deletable, but not served and not editable until you are back under the cap or
licensed for more. The same happens when a licence expires — there is no grace
period after the date. The panel warns before it: a banner from seven days
out, and the `panel.license_expiring` event 30, 14, 7 and 1 days before.

## Buying one

Open **License** in the menu and press **Buy a licence**. The vendor's
checkout page opens in a new tab, in the panel's language, with no account to
create:

1. Choose a plan. Prices are in US dollars; a gateway paying in another
   currency converts at its own rate.
2. Leave a name and an email if you want the vendor to be able to reach you —
   both are optional.
3. Pay by **card** (Stripe), **crypto** (NowPayments) or by **uploading a
   receipt** of a transfer, following the instructions the page shows.

There is **no key to paste**. Once the payment is confirmed the panel collects
its licence on its own within a minute or two, and the panel says *Licence
installed*. A receipt waits until the vendor has looked at it — the page and
the panel both say so, and you can close the tab; if it is not accepted, the
page says that too and you can send another. A crypto payment that arrives
short is counted, and the page asks for the rest.

Changed your mind? Until money is on its way, the page offers **Choose another
plan** and **Cancel the purchase** below the payment methods. A cancelled
purchase charges nothing, and the panel stops waiting for it.

The link the panel opens works for that panel only: somebody else opening it
can pay, but the licence still goes to the panel that asked for it. It is
valid for 24 hours to pay; once paid, until the licence is delivered, up to 30
days.

A key the vendor sends you by hand still works: paste it under **Activate**.

## Renewing and upgrading

On a licensed panel the button reads **Renew or upgrade**, and the checkout
page shows every plan this licence can move to, already priced:

| You choose | You pay | Expiry |
| --- | --- | --- |
| Renew the same plan | the plan's price | a period added **after** the current expiry — renewing early loses nothing |
| A plan with higher caps | the difference, for the days you have left | unchanged |
| Another period with the same caps (monthly ↔ yearly) | the new plan's full price | its period added after the current expiry |
| A lifetime plan | its price, minus what your remaining days are worth | never |

A plan with lower caps is not offered, and neither is a higher one whose period is shorter than the days you have left — with months paid ahead, choose its yearly or lifetime plan. An expired licence renews the same way,
from its **License** page, and is back as soon as the payment is confirmed.

## Moving to a new server

A licence is bound to the server's hardware fingerprint (`nexora-panel hwid`
prints it). To move:

1. Install the panel on the new server and restore your backup — on the setup
   wizard's first screen, *Moving from another server? Restore a backup*. The licence comes with it, but it
   is bound to the old server, so the new one runs on the free tier.
2. Open **License** and press **Move the licence to this machine**. The checkout
   page offers the move; it is free.

It goes through at once when **the old server has not been in contact with the
licence service for 72 hours** and the licence has moved **fewer than twice in
the last twelve months**. Otherwise the page says why and sends the request to
the vendor, who approves it by hand; the panel installs the licence as soon as
that happens. So the quickest move is: stop the old server, wait three days,
then move.

From then on the old server is refused at its next check-in and falls to the
free tier — a copy of the database left running elsewhere does not keep the
licence.

## Staying in contact

The panel checks in with `license.nexora-panel.org` over HTTPS every six hours
— every minute while a purchase is open, every ten while a receipt or a move
waits for the vendor. That check-in is how a renewal, an upgrade or a move
reaches it, and how the vendor revokes a licence. The answers are signed with the vendor's key, and the panel ignores
any it cannot verify — a proxy or a server of your own answering in the
service's place counts as no answer.

**After 14 days without a verified check-in the panel falls to the free tier**
until the next one succeeds, which restores the licence at once. It warns from
day 7 (the banner and the `panel.license_unverified` event). If the server sits
behind a firewall, allow outbound HTTPS to `license.nexora-panel.org`.

**Recheck online** on the **License** page checks in right away and says what
happened: *Verified with the licence service*; *something answered, but not
provably the licence service* — the answer did not count; or *the licence
service could not be reached*.

## Questions and refunds

There is no refund button, in the panel or on the checkout page. Write or call
the vendor: the email address and phone number are at the bottom of every
checkout page. Reversing a payment in the gateway does not remove a licence by
itself — the vendor decides that.
