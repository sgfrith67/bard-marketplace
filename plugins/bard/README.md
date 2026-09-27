# BARD — Bonhams Auction Research Database

BARD connects Claude to Bonhams' own Supabase-backed archive of auction results — about 200,000 lots from Bonhams, Christie's, Sotheby's, and Phillips (2013–present), across jewellery and other departments — and adds four skills on top of it.

## Components

| Component | Type | Purpose |
|---|---|---|
| `BARD_data` | MCP connector (HTTP) | The BARD Zuplo gateway at `https://bonhams-bard-main-39baa01.d2.zuplo.dev/mcp`. Offers `query_table`, which reads rows from the `Auction_results` table (column selection, ordering, limit/offset, and filters where the gateway supports them). No Supabase account or token needed. |
| `comparable-sales` | Skill | Finds comparable prior sales for a described jewellery piece or gemstone. |
| `lot-estimate` | Skill | Builds a reasoned pre-sale low/high estimate range from comparables, with sourcing shown. |
| `auction-query` | Skill | Answers ad-hoc questions — sell-through, top sales, volume — from filtered reads and `totalRows` counts. |
| `bard-home` | Skill | Builds and publishes the BARD home page: a Specialist view (comparables request builder with Ask Claude chat, top recent lots, estimate performance) and a Management view (live-auction share, regions, monthly trend, reliance on top lots). |

## Setup

Nothing to configure: installing the plugin adds the `BARD_data` connector, and the skills use it directly.

## What the gateway supports today

| Capability | Status |
|---|---|
| Read rows from `Auction_results`, choose columns, page with limit/offset | Works |
| Row count for a query (`totalRows`) | Works |
| Filter rows (status, house, date range, keyword `ilike`) | **Needed** for comparables, estimates and most stats. Until the gateway accepts filters, the skills say so instead of paging the whole table |
| Sort by `auction_date` across the whole table | Times out without an index on `auction_date` |
| SQL and the `bard` views (home page live data, the chat's BARD search) | Not available through the gateway. The home page shows its saved snapshot unless the viewer has a SQL-capable claude.ai Supabase connector |

## Usage

- *"Find comps for an 18k gold turquoise and diamond ring, around 4 carats total diamond weight"* → `comparable-sales`
- *"What should I estimate this piece at — [description]?"* → `lot-estimate`
- *"Open BARD"* / *"Refresh the BARD home page"* → `bard-home`
- *"What's Bonhams' sell-through rate this year vs. last year?"* / *"Show the top 10 jewellery sales at Christie's in 2025"* → `auction-query`

## Home page notes

The `bard-home` page is published as a claude.ai Artifact. Its live data comes from one SQL query over the `bard.*` database views (`skills/bard-home/references/admin-setup.sql`, maintained by Investair — the skill never creates them), so it needs a claude.ai connector with `execute_sql` for the BARD project. Without one, the page shows its bundled snapshot, and Ask Claude answers without searching BARD.

## Data and security notes

- **`Auction_results` columns:** `id` (primary key), `lot_number`, `auction_number`, `auction_name`, `auction_date`, `auction_house`, `department`, `auction_url`, `lot_title`, `lot_description`, `est_low`, `est_high`, `hammer_price`, `sold_price`, `status`, `withdrawn`, `lot_url`, `published`, `object_id`, `image_url`, `currency`.
- `department` now spans several departments (jewellery, watches, fashion and more). The skills filter to jewellery rather than assuming it.
- Prices span seven currencies (USD, GBP, HKD, CHF, EUR, AUD, CNY); the skills are written to avoid blending currencies without saying so.
- `auction_date` is stored as ISO text (`YYYY-MM-DD`), not a native date type — string comparisons work for ranges.
- **Writes:** the plugin only reads. The table's Row Level Security, however, lets the `anon` role **insert and update** rows for the four houses (policies `weekly_load_insert` and `weekly_load_update`, used by the weekly loader), alongside `SELECT` for `anon` and `authenticated`. Writes are therefore *not* blocked at the database level for anyone holding the project's anon key. Keep the gateway read-only and the anon key out of shared places.
- This plugin is independent of the existing `jewellery-auction-results`/`lot-estimate-guide` plugins, which run on a separate (MySQL/Investair) backend.
