---
name: bard-home
description: Build and publish the BARD (Bonhams Auction Research Database) home page, an interactive page with a Specialist view (comparables request builder, top recent lots, estimate performance) and a Management view (Bonhams live-auction share, regions, monthly trend, reliance on top lots) that loads live jewellery auction data from BARD each time it's opened. Use this skill whenever a Bonhams user asks for the BARD home page, BARD dashboard, "open BARD", "set up BARD", "/bard-home", the jewellery market-share or estimate-performance page, or wants to refresh, rebuild, restyle or re-publish that page, even if they don't say "home page".
compatibility: Needs the Artifact tool (claude.ai) to publish, and a Supabase connector with read access to the BARD project for live data.
---

# BARD home page

This skill publishes one self-contained web page for the person running it. The page queries BARD live, through that person's own Supabase connector, every time it's opened, so most runs only need to build and publish. There's nothing to recalculate by hand.

Everything the page needs is bundled:

- `assets/template.html`: the page (Bonhams styling, both views, live-data loader)
- `assets/model.sql`: the single read-only query the page runs
- `assets/snapshot.json`: fallback data shown only when live data can't load
- `scripts/build_page.py`: fills the template and writes the HTML
- `references/admin-setup.sql`: database views the page depends on (Investair admins only, never run by this skill)

## Workflow

### 1. Find a SQL connector

The page's live data and the chat's BARD search both run SQL (`execute_sql`) over the `bard` database views. **The plugin's own connector, `BARD_data`, is the Zuplo gateway: it only offers `query_table` (reads rows from `public` tables) and can't run SQL or reach the `bard` views.** So:

- **For steps 2–3 and for the published page**, you need a **claude.ai Supabase connector** with an `execute_sql` tool, pointed at the BARD project (for example the URL `https://mcp.supabase.com/mcp?project_ref=yxnechonpwuhhsatstgj&read_only=true`). Its tools appear as `mcp__<id>__execute_sql`. Note its display name exactly as written (for example `Bonhams-BARD`); if the session lists its connectors by name, take it from there. Plugin connectors run inside Claude Code only, so a published page can't reach them anyway.
- **If there's no such connector**, carry on without live data: skip steps 2–3, build with the bundled snapshot, and publish with `capabilities: {"sample": {}}` only (no `mcp`). The page shows the snapshot, and Ask Claude still works but answers without searching BARD. Tell the user that live data and the chat's search need a SQL-capable claude.ai connector, or new gateway endpoints for the page's data (Investair's job).

### 2. Check BARD is reachable

Run this through `execute_sql` with `project_id` `yxnechonpwuhhsatstgj`:

```sql
select auction_house, latest_sale_date, caveat from bard.meta_v order by auction_house;
```

This also wakes the database, which pauses when idle.

- **Paused, inactive, or timed out:** wait about ten seconds and run the query once more. It usually wakes on the second try.
- **`bard.meta_v` does not exist:** the database views haven't been set up. Stop and tell the user to contact Investair. Don't try to create the views yourself.
- **Permission or auth error:** the user's connector can't see the BARD project. Explain that, then continue with the snapshot version.

Keep the four rows. Each house's latest sale date and caveat go in the summary at the end.

### 3. Decide whether to refresh the fallback snapshot

The snapshot only appears when someone opens the page without working live data. Refresh it when the user asks for fresh data or a new snapshot, when they plan to share the page with colleagues who may not have the connector, or when the build step reports `snapshot_age_days` over 30. Otherwise use the bundled one.

To refresh:

1. Run the full contents of `assets/model.sql` through `execute_sql`.
2. Write the tool's text result, unchanged, to `bard_result.txt` in a working directory (`/home/claude/` on claude.ai, or the session scratchpad in Claude Code). The build script strips the wrapper itself.
3. Pass that file as `--result` in step 4.

### 4. Build

```bash
python <this skill's directory>/scripts/build_page.py \
  --server "<claude.ai connector name>" \
  --out <outputs dir>/bard-home.html
  # <outputs dir> is /mnt/user-data/outputs on claude.ai, or the session scratchpad in Claude Code
  # add --result <working dir>/bard_result.txt if you refreshed the snapshot
  # add --yellow "#RRGGBB" only if the user gives Bonhams' exact yellow
```

Use the connector display name from step 1 for `--server` (any value is fine when there's no SQL connector; the page then shows the snapshot). The script prints JSON with the output path and snapshot age. If it exits with an error, read the message: a malformed `--result` file is the usual cause. Retry without `--result` rather than hand-editing the template.

### 5. Publish, or update the existing page

People re-run this skill, so update their existing page where there is one rather than creating duplicates. Call the Artifact tool with `action: "list"` (their own artifacts) and look for the title **BARD — Bonhams Auction Research Database**.

Publish with:

- `file_path`: the `--out` path from step 4
- `title`: `BARD — Bonhams Auction Research Database`
- `favicon`: 💎
- `capabilities`: `{"mcp": {"servers": [{"server": "<claude.ai connector name from step 1>", "tools": ["execute_sql"]}]}, "sample": {}}`
- `url`: the existing page's link, if step 5 found one. Omit it to create a new page.
- With no SQL connector (step 1), use `capabilities: {"sample": {}}` instead.

The `mcp` declaration lets the published page call the viewer's connector; without it the page can only ever show the snapshot. The `sample` declaration powers the **Ask Claude** chat in Price a piece; without it the chat is hidden and only Copy request remains. Both are asked for once, the first time the viewer uses them.

If the Artifact tool isn't available, for example outside claude.ai, present the HTML file instead. Tell the user it will show the snapshot only, because live data needs the page opened in claude.ai.

### 6. Tell the user what they've got

Keep it short:

- **Link:** the page link, and whether it's new or an update of their existing page.
- **Live data:** the first time they open it, Claude asks permission to use their Supabase connector once. After that it loads live, and shows "Waking the database…" for up to a minute if BARD has been idle.
- **Views:** Specialist and Management switch at the top, and USD/AUD converts every figure.
- **Ask Claude:** in Price a piece, *Ask Claude* sends the generated request to Claude inside the page. Claude searches BARD through their connector and replies with comparables and an estimate, and they can ask follow-ups. It runs on the viewer's own Claude usage.
- **Data caveats:** any caveats from step 2, especially a house with no sales captured recently.
- **Snapshot:** whether the fallback snapshot was refreshed, and its date.

## Things that trip people up

| What they see | Cause | What to tell them |
|---|---|---|
| "Showing the saved snapshot…" | Page opened outside claude.ai, or connector not added | Open the page in claude.ai with the Supabase connector connected |
| "Add the Supabase connector…" | No connector with the name the page expects | Add it in Settings → Connectors, or rebuild with `--server` set to their connector's name |
| "Reconnect Supabase…" | Connector sign-in lapsed | Reconnect in Settings → Connectors, then press Try again |
| "Live data is turned off for this page" | They declined the connector prompt | Re-publish (step 5) and accept the prompt on next open |
| "BARD reported an error" | Database hiccup or paused | Press Try again; if it persists, run step 2 to diagnose |
| Competitor figures stop in a past month | Scraper hasn't captured newer sales | Expected; the page's data notes say so. Investair maintains the scrapers |

## How the page calculates things

Answer questions about the numbers from `references/page-guide.md`. Read it when the user asks why a figure is what it is, or wants a section changed.

## Changing the page

For small requests (wording, which sections show, colours), edit `assets/template.html` in place, rebuild, and re-publish to the same link. Keep the placeholders (`__SNAPSHOT__`, `__MODEL_SQL__`, `__PROJECT_ID__`, `__SERVER__`, `__YELLOW__`), because the build fails loudly if one goes missing.

If a change needs data the page doesn't already receive, extend `assets/model.sql`: add a field to its final `json_build_object`, and read it in the template's JS. Keep the query read-only, and never build SQL from anything a viewer types into the page.

Structural changes to the `bard` database views are for Investair. Point the user there rather than altering the database.
