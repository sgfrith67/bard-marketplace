---
name: auction-query
description: >
  This skill should be used when the user asks ad-hoc questions about the
  BARD auction archive that aren't a single-item comparables search or
  estimate — e.g. "what's the sell-through rate for [house/period]", "show
  top sales in [year]", "how has [category] pricing trended", "how many
  lots did [house] sell last quarter". Runs read-only SQL against the BARD
  Supabase connector's Auction_results table for lookups and aggregate
  stats.
metadata:
  version: "0.3.0"
---

Answer open-ended questions about the auction archive by querying `public."Auction_results"` through the `BARD_data` connector (or `bard-supabase` if `BARD_data` isn't connected) (read-only — `SELECT` only, no writes are possible against this connector).

## Schema

Same table as `comparable-sales`/`lot-estimate`: `lot_number`, `auction_number`, `auction_name`, `auction_date` (text, ISO `YYYY-MM-DD`), `auction_house` (`Bonhams`/`Christies`/`Sothebys`/`Phillips`), `department` (currently always `Jewelry`), `lot_title`, `lot_description`, `est_low`, `est_high`, `hammer_price`, `sold_price`, `status` (`SOLD`/`NOT_SOLD`/`UNSOLD`/null), `withdrawn` (`No`/null), `currency`, `lot_url`, `image_url`.

## Common patterns

- **Sell-through rate**: `count(*) filter (where status = 'SOLD') / count(*)::numeric` over the relevant slice (by house, date range, etc.). Decide whether to include or exclude rows with null `status` and say which you did.
- **Top sales**: order by `sold_price desc`, filtered to `status = 'SOLD'`, within whatever house/date/currency slice was asked for.
- **Price trend over time**: bucket by year (`left(auction_date, 4)`) or by `auction_name`, and aggregate `sold_price`/`hammer_price` — always split or note by `currency` since the archive mixes seven currencies, and never sum/average raw prices across currencies.
- **Premium over estimate**: compare `sold_price` (or `hammer_price`) to `est_low`/`est_high` per lot to see whether sales landed inside, above, or below estimate.
- **Volume counts**: straightforward `count(*)` with `group by auction_house`, `group by auction_name`, or date-range filters (`auction_date >= '2025-01-01'` — string comparison works because dates are stored as ISO text).

## Guidance

- Always state which filters were applied (status, date range, currency, house) alongside the answer so the number is reproducible.
- When a question is ambiguous (e.g. "recent" with no window given), pick a reasonable default (last 12 months) and say so, rather than asking unless the choice would materially change the answer.
- For anything mixing currencies, either group by `currency` in the output or restrict to one currency and say which.
- Cross-reference `withdrawn` and `status` — a withdrawn lot has no meaningful price and should generally be excluded from price stats even if `status` is null.
