# How the BARD home page calculates its figures

Use this reference to explain a number or to change a section. All figures come from one query (`assets/model.sql`), which reads the `bard` views in the BARD Supabase database.

## Scope rules applied everywhere

- **Jewellery only:** a lot counts when it sold in a *dedicated jewellery sale*, meaning the sale name contains "jewel" and not watch, handbag, fashion, pens or wine. Lots from mixed or single-owner sales are tagged in the database but left out of the page.
- **Live vs online:** sales named "Weekly" or "Online" are online, and everything else is live. BARD captures Bonhams' full online calendar but mostly only competitors' flagship live sales, so **market share and concentration use live auctions only**. Bonhams' online sales have their own section.
- **Values:** buyer's total (`sold_price`) is the only figure all four houses publish. Hammer exists for Bonhams only, and estimate performance uses hammer because estimates are set against it.
- **Currency:** every value is converted to USD at the **latest ECB reference rate**, refreshed daily inside the database, and the same rate applies to every period. Year-on-year changes therefore exclude currency movement. AUD figures on the page divide by the latest AUD rate.
- **Financial year:** July to June, labelled by the June year (FY26 = Jul 2025 – Jun 2026). Share charts show only completed years. The current year appears once competitor sales for it are captured.
- **Region:** taken from the city in the sale name (Geneva → Switzerland, Hong Kong → Asia, and so on), falling back to the sale currency.

## Specialist view

| Section | What it shows |
|---|---|
| Price a piece | Builds a comparables request from the form. Nothing is queried; the text is for pasting into Claude with the Bonhams plugin |
| Top lots, last six months | Top 6 lots per house by USD buyer's total from the last 180 days (three per house on "All houses") |
| How Bonhams estimates are landing | Bonhams sold lots with an estimate, by item type: share hammering below low estimate, within, or above high estimate, plus median hammer ÷ low estimate. Item type comes from keywords in the lot title |
| Data notes | Latest sale captured per house and each house's caveats |

## Management view

| Section | What it shows |
|---|---|
| Headline figures | Bonhams live value for the chosen year and change on the prior year; share of the four houses' live value and rank; sell-through (sold ÷ offered, live and online); current year to date against the same day last year, live and online |
| Share of live value | Each house's share of live buyer's total, by year, with a table of sales, lots sold, value, share and average lot |
| Bonhams by region | Bonhams live value per region and its share of captured live value there. Where Bonhams had no sale, the leading house is named |
| Live sale value by month | Last 24 months, one small chart per house, each on its own scale |
| Reliance on top lots | Share of each house's live value from its top 10% and top 5% of lots, and from its single top lot |
| Bonhams online sales | Online sales, lots, value, share of Bonhams' total and average lot |

## Caveats the page shows automatically

These come from `bard.meta_v` and clear themselves when the data improves:

- **Unknown lot status:** more than 2% of a house's lots lack a sold/unsold status (currently Sotheby's). Its sell-through isn't reported and its lot counts are marked indicative.
- **No hammer prices:** a house publishes buyer's total only.
- **No recent sales:** no sale has been captured for more than 60 days, which usually means the scraper needs attention.
