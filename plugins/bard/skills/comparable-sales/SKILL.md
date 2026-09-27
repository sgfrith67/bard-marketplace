---
name: comparable-sales
description: >
  This skill should be used when the user asks to "find comparable sales",
  "find comps for this lot", "search auction history for [item]", "what has
  a similar piece sold for", or wants to see prior results from the BARD
  auction archive for a jewellery piece or gemstone they describe. Queries
  the BARD Supabase connector's Auction_results table, covering lots from
  Bonhams, Christie's, Sotheby's, and Phillips.
metadata:
  version: "0.3.0"
---

Use the `BARD_data` connector's `execute_sql` tool (fall back to the `bard-supabase` connector if `BARD_data` isn't connected) to query `public."Auction_results"` (the mixed-case name requires double quotes in Postgres).

## Table reference

| Column | Type | Notes |
|---|---|---|
| `lot_number`, `auction_number` | text | identifiers |
| `auction_name` | text | e.g. "Fine Jewelry: California" |
| `auction_date` | text | ISO `YYYY-MM-DD` string; string comparison sorts and ranges correctly |
| `auction_house` | text | `Bonhams`, `Christies`, `Sothebys`, `Phillips` |
| `department` | text | currently always `Jewelry` |
| `lot_title`, `lot_description` | text | free text; description holds materials, gemstone type, carat weights, maker, period, dimensions |
| `est_low`, `est_high` | numeric | pre-sale estimate range |
| `hammer_price` | numeric | price at fall of hammer, excludes buyer's premium |
| `sold_price` | numeric | total price paid, includes buyer's premium; null if unsold |
| `status` | text | `SOLD`, `NOT_SOLD`, `UNSOLD`, or null |
| `withdrawn` | text | `No` or null (no `Yes` values observed in the archive) |
| `currency` | text | `USD`, `GBP`, `HKD`, `CHF`, `EUR`, `AUD`, `CNY` — **do not sum or average across currencies without noting the mix** |
| `lot_url`, `image_url` | text | links back to the source listing |

Data spans 2013–present across the four houses. `lot_description` is the richest field for matching — it contains stone type, cut, carat weight, metal, maker's marks, and period detail as free text.

## Finding comparables

1. Extract the distinguishing features from the item the user describes: gemstone/material, carat weight (if given), metal, style/period, maker or brand, and any other distinctive detail.
2. Query with `ILIKE '%term%'` across `lot_title` and `lot_description`, combining the most distinctive 2-4 terms with `AND`/`OR` as appropriate — don't over-constrain on the first pass; loosen or tighten based on result count.
3. Filter to completed, valid sales unless the user asks otherwise:
   ```sql
   where status = 'SOLD' and (withdrawn is null or withdrawn = 'No')
   ```
4. If a carat weight was given, note that weights live inside `lot_description` as free text (e.g. "estimated total diamond weight 3.25 carats") — filter loosely by keyword and then read descriptions to judge closeness, rather than trying to parse an exact numeric range in SQL.
5. Order by `auction_date desc` and cap at a reasonable number (`limit 15-20`) unless the user wants the full set.
6. If results are too sparse, broaden the search terms (drop a qualifier); if too broad, add a distinguishing term (metal, maker, period) rather than lowering the limit further.

## Presenting results

Show each comparable as: auction house, auction name/date, lot title, estimate range, hammer price, sold price (with currency), and the `lot_url`. Group or flag by currency when mixing currencies in one table. Note when a lot was `NOT_SOLD`/`UNSOLD` if the user asked to include those — they indicate demand at that estimate level, not a sale.

Do not convert currencies yourself; present the currency alongside each figure and let the user apply their own FX rate if they need a single-currency comparison.
