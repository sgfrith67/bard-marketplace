---
name: comparable-sales
description: >
  This skill should be used when the user asks to "find comparable sales",
  "find comps for this lot", "search auction history for [item]", "what has
  a similar piece sold for", or wants to see prior results from the BARD
  auction archive for a jewellery piece or gemstone they describe. Reads the
  Auction_results table through the BARD_data connector (Zuplo gateway),
  covering lots from Bonhams, Christie's, Sotheby's, and Phillips.
metadata:
  version: "0.5.0"
---

Read the `Auction_results` table through the `BARD_data` connector's `query_table` tool (if tools are deferred, search for "query_table"). The connector is the BARD Zuplo gateway, `https://bonhams-bard-main-39baa01.d2.zuplo.dev/mcp`.

## How to call `query_table`

- `table`: always `Auction_results` (exact case; no quotes, no schema prefix).
- `select`: a comma-separated column list. Always ask only for the columns you need, because `lot_description` is long.
- `limit` / `offset`: page size (default 50) and paging.
- `order`: e.g. `sold_price.desc`. **Avoid ordering by `auction_date` across the whole table**: without an index it times out ("canceling statement due to statement timeout"). Order within a filtered set, or sort the returned rows yourself.
- **Filters:** check the tool's input schema each time. If it offers a filter parameter (PostgREST style, e.g. `status=eq.SOLD`, `auction_house=eq.Bonhams`, `lot_description=ilike.*sapphire*`, `auction_date=gte.2024-01-01`), use it for every search. If it doesn't, **stop and tell the user**: the gateway can't search by keyword yet, so a comparables search would mean paging through ~200,000 rows. Don't try to page the whole table.

## Table reference: `Auction_results`

| Column | Type | Notes |
|---|---|---|
| `id` | int8 | primary key (identity) |
| `lot_number` | text | lot identifier within a sale |
| `auction_number` | text | sale identifier |
| `auction_name` | text | e.g. "Fine Jewelry: California" |
| `auction_date` | text | ISO `YYYY-MM-DD` string; string comparison sorts and ranges correctly |
| `auction_house` | text | `Bonhams`, `Christies`, `Sothebys`, `Phillips` |
| `department` | text | the archive now spans several departments (jewellery, watches, fashion and more), so **filter or check it** rather than assuming jewellery |
| `auction_url` | text | link to the sale |
| `lot_title`, `lot_description` | text | free text; the description holds materials, gemstone type, carat weights, maker, period, dimensions |
| `est_low`, `est_high` | numeric | pre-sale estimate range |
| `hammer_price` | numeric | price at the fall of the hammer, excluding buyer's premium (mostly Bonhams only) |
| `sold_price` | numeric | total price paid, including buyer's premium; null if unsold |
| `status` | text | `SOLD`, `NOT_SOLD`, `UNSOLD`, or null |
| `withdrawn` | text | `No` or null |
| `lot_url`, `image_url` | text | links back to the source listing |
| `published` | text | publication flag or date from the source listing |
| `object_id` | text | the source site's object identifier |
| `currency` | text | `USD`, `GBP`, `HKD`, `CHF`, `EUR`, `AUD`, `CNY`: **do not sum or average across currencies without noting the mix** |

About 200,000 lots across the four houses. `lot_description` is the richest field for matching.

## Finding comparables

1. Extract the distinguishing features from the item: gemstone or material, carat weight (or range), metal, style or period, maker or brand, and any other distinctive detail.
2. Filter to completed, valid sales unless the user asks otherwise: `status` = `SOLD`, and `withdrawn` null or `No`. Restrict to jewellery: `department` for jewellery, or a sale name containing "jewel".
3. Match the 2–4 most distinctive terms with `ilike` on `lot_title` or `lot_description`. Don't over-constrain on the first pass; loosen or tighten based on the result count.
4. Carat weights live inside `lot_description` as free text (e.g. "estimated total diamond weight 3.25 carats"). Filter loosely by keyword, then read descriptions to judge closeness. If the user gave a carat range, keep only lots whose main stone falls inside it, and show each lot's weight.
5. Select only `auction_house, auction_name, auction_date, lot_title, lot_description, est_low, est_high, hammer_price, sold_price, currency, lot_url`, and cap at 15–20 rows unless the user wants more. Sort the returned rows by date yourself.
6. If results are too sparse, drop a qualifier; if too broad, add a distinguishing term (metal, maker, period) rather than lowering the limit.

## Presenting results

Show each comparable as: auction house, sale name and date, lot title, estimate range, hammer price, sold price (with currency), and the `lot_url`. Group or flag by currency when mixing currencies in one table. Note when a lot was `NOT_SOLD`/`UNSOLD` if the user asked to include those: they show demand at that estimate level, not a sale.

Don't convert currencies yourself; present the currency alongside each figure and let the user apply their own FX rate if they need a single-currency comparison.
