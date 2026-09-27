# BARD — Bonhams Auction Research Database

BARD connects Claude to Bonhams' own Supabase-backed archive of jewellery auction results — currently ~50,000 lots from Bonhams, Christie's, Sotheby's, and Phillips (2013–present) — and adds four skills on top of it.

## Components

| Component | Type | Purpose |
|---|---|---|
| `BARD_data` | MCP connector (HTTP) | Hosted Supabase MCP at `https://mcp.supabase.com/mcp?project_ref=yxnechonpwuhhsatstgj&read_only=true` — read-only, scoped to the BARD project. Signs in with your Supabase account (OAuth) the first time it's used; no token to manage. Preferred by all skills. |
| `bard-supabase` | MCP server (fallback) | Read-only connection to the BARD Supabase project (`Auction_results` table). Uses the official Supabase MCP server in `--read-only` mode, scoped to this one project via `--project-ref`. |
| `comparable-sales` | Skill | Finds comparable prior sales for a described jewellery piece or gemstone. |
| `lot-estimate` | Skill | Builds a reasoned pre-sale low/high estimate range from comparables, with sourcing shown. |
| `auction-query` | Skill | Answers ad-hoc questions — sell-through rates, top sales, price trends, volume — via SQL over the archive. |
| `bard-home` | Skill | Builds and publishes the BARD home page: a live Specialist view (comparables request builder, top recent lots, estimate performance) and Management view (live-auction share, regions, monthly trend, reliance on top lots). |

## Setup

**Recommended — `BARD_data`:** nothing to configure. The first time a skill uses it, Claude prompts you to sign in to Supabase (via /mcp in Claude Code, or the connector's Connect button in the app). Your Supabase account needs access to the BARD project.

**Fallback — `bard-supabase`:** only needed if you can't use `BARD_data`.

The connector needs a Supabase **personal access token** with (at minimum) read access to the BARD project:

1. In the Supabase dashboard, go to **Account → Access Tokens** and generate a new token.
2. Set it as the `SUPABASE_ACCESS_TOKEN` environment variable wherever this plugin runs.

The connector is locked to the BARD project only (`--project-ref=yxnechonpwuhhsatstgj`) and runs in `--read-only` mode, so it cannot modify data or reach other Supabase projects even if the token has broader scope. As a second layer of defence, the underlying table's Row Level Security policies only grant `SELECT` — there's no `INSERT`/`UPDATE`/`DELETE` policy at all, so writes are rejected at the database level regardless of the token used.

No other setup is required — the skills query the connector directly.

## Usage

- *"Find comps for an 18k gold turquoise and diamond ring, around 4 carats total diamond weight"* → `comparable-sales`
- *"What should I estimate this piece at — [description]?"* → `lot-estimate`
- *"Open BARD"* / *"Refresh the BARD home page"* → `bard-home`
- *"What's Bonhams' sell-through rate this year vs. last year?"* / *"Show the top 10 jewellery sales at Christie's in 2025"* → `auction-query`

## Home page notes

The `bard-home` page is published as a claude.ai Artifact and loads live data through the viewer's **`BARD_data`** connector (or a claude.ai Supabase connector) with access to the BARD project. Without it, the page falls back to a bundled snapshot. It depends on the `bard.*` database views in `skills/bard-home/references/admin-setup.sql`, which Investair maintains — the skill never creates them.

## Data notes

- `department` is currently always `Jewelry` — the archive doesn't yet cover other Bonhams departments.
- Prices span seven currencies (USD, GBP, HKD, CHF, EUR, AUD, CNY); the skills are written to avoid blending currencies without saying so.
- `auction_date` is stored as ISO text (`YYYY-MM-DD`), not a native date type — string comparisons and `left(auction_date, 4)` for year work correctly against it.
- This plugin is independent of the existing `jewellery-auction-results`/`lot-estimate-guide` plugins, which run on a separate (MySQL/Investair) backend. It's possible those could eventually consolidate onto BARD, but that migration is out of scope here.
