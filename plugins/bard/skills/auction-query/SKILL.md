---
name: auction-query
description: >
  This skill should be used when the user asks ad-hoc questions about the
  BARD auction archive that aren't a single-item comparables search or
  estimate — e.g. "what's the sell-through rate for [house/period]", "show
  top sales in [year]", "how has [category] pricing trended", "how many
  lots did [house] sell last quarter". Reads the Auction_results table
  through the BARD_data connector (Zuplo gateway) for lookups and stats.
metadata:
  version: "0.5.0"
---

Answer open-ended questions about the auction archive by reading the `Auction_results` table through the `BARD_data` connector's `query_table` tool (the BARD Zuplo gateway). The gateway is read-only for this plugin: it reads rows and never writes.

## Schema

Same table as `comparable-sales`/`lot-estimate`: `id`, `lot_number`, `auction_number`, `auction_name`, `auction_date` (text, ISO `YYYY-MM-DD`), `auction_house` (`Bonhams`/`Christies`/`Sothebys`/`Phillips`), `department` (several departments now, so filter to the one asked about), `auction_url`, `lot_title`, `lot_description`, `est_low`, `est_high`, `hammer_price`, `sold_price`, `status` (`SOLD`/`NOT_SOLD`/`UNSOLD`/null), `withdrawn` (`No`/null), `lot_url`, `published`, `object_id`, `image_url`, `currency`. See `comparable-sales` for column notes and the `query_table` call rules.

## What the gateway can and can't do

`query_table` returns rows, with `select`, `order`, `limit` and `offset`, plus filters if its input schema offers them. The response also reports `totalRows` for the query. It has **no aggregation** (no count, sum or group by) and no SQL.

- **Counts:** make a filtered call with `limit: 1` and read `totalRows`. For example, lots sold at Bonhams in 2025 = `totalRows` with `auction_house` = `Bonhams`, `status` = `SOLD`, and `auction_date` from `2025-01-01` to `2025-12-31`.
- **Sell-through:** two counts over the same slice, sold ÷ offered. Say whether null `status` rows were included.
- **Top sales:** filter the slice, then `order: sold_price.desc` with a small `limit`. Ordering a filtered slice is fine; ordering the whole table by `auction_date` times out.
- **Totals, averages, trends by year or month:** these need every matching row. Only do it when the slice is small (a single sale, or a few hundred lots): page through with `select` limited to the columns you need, and total it yourself. For anything larger, say that this needs an aggregate endpoint on the gateway rather than paging thousands of rows.
- **No filter parameter on the tool:** most questions can't be answered. Say so and explain that the gateway needs filter support.

## Guidance

- Always state which filters were applied (status, date range, currency, house, department) alongside the answer, so the number is reproducible.
- When a question is ambiguous (e.g. "recent" with no window given), pick a reasonable default (last 12 months) and say so, rather than asking, unless the choice would materially change the answer.
- For anything mixing currencies, split the output by `currency` or restrict it to one currency and say which. Never sum or average raw prices across currencies.
- Cross-reference `withdrawn` and `status`: a withdrawn lot has no meaningful price and should generally be excluded from price stats even if `status` is null.
