---
name: lot-estimate
description: >
  This skill should be used when the user asks to "estimate this piece",
  "what should I estimate this lot at", "suggest an estimate range for
  [item]", or wants a pre-sale low/high estimate derived from the BARD
  auction archive rather than a plain comparables list. Builds on the BARD
  Supabase connector to research comparables and reason about an estimate
  range.
metadata:
  version: "0.3.0"
---

Produce a reasoned pre-sale estimate range for a piece the user describes, grounded in comparable sales from `public."Auction_results"` via the `BARD_data` connector (or `bard-supabase` as a fallback). This is a research aid for a specialist, not a substitute for their judgment — always frame the output as a starting point, not a final estimate.

## Process

1. **Gather the item's features** from the user: gemstone/material, carat weight, metal, maker/brand, period/style, condition notes. Ask for anything critical that's missing (carat weight and material are usually essential; don't ask about everything).
2. **Search for comparables** using the same approach as the `comparable-sales` skill: `ILIKE` matching on `lot_title`/`lot_description`, filtered to `status = 'SOLD'` and not withdrawn. Pull 8-20 close comparables — prefer fewer, closer matches over a large loose set.
3. **Read the comparables' `lot_description` values** to judge true closeness (carat weight, quality, maker) beyond what the keyword match guarantees, and set aside any that turn out to be a poor match.
4. **Reason about the range**, not just an average:
   - Look at the spread of `sold_price` (and `hammer_price`) among the closest comparables, not just the mean — a tight cluster supports a narrow estimate, a wide spread means say so.
   - Where carat weight is known, compare price-per-carat across comparables of similar quality rather than raw price, when the comparables vary in size.
   - Note how comparables' `sold_price` related to their own `est_low`/`est_high` (sold within range, above, or below) — this shows whether estimates in this category tend to be conservative or aggressive relative to outcomes, which should shift where you set the new range.
   - Weight recent sales (last 1-3 years) more heavily than older ones; note if the market for this category looks like it's moved.
   - If currencies differ across comparables, keep them separate rather than blending, and pick the estimate currency the user needs (or present multiple currency clusters separately).
5. **Propose a low/high range** and briefly justify it against the comparables used — do not just output a number with no reasoning.

## Output format

- A short summary of the item as understood.
- The comparables table used (auction house, date, title, estimate, hammer, sold price, currency, `lot_url`), so the specialist can verify the sources.
- The proposed estimate range with 2-4 sentences of reasoning tied directly to the comparables.
- A one-line caveat that this is derived from archive comparables only and should be reviewed against condition, provenance, and current market judgment before use.

If fewer than ~5 reasonable comparables exist, say so explicitly and either broaden the search (note what was loosened) or flag that the estimate is low-confidence due to sparse data — don't present a confident-sounding range from a thin sample.
