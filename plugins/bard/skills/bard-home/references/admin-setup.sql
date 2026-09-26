-- =====================================================================
-- BARD home page — summary views (POC)
-- APPLIED 26 Sep 2026 as migrations bard_fx_rates + bard_home_views
-- Project: yxnechonpwuhhsatstgj  |  Source: public."Auction_results"
--
-- Design notes
--  * Views live in their own schema (bard), which is NOT exposed through the
--    Supabase REST API, and anon/authenticated are revoked. Views in public
--    would be reachable via the API and would run with owner rights,
--    sidestepping the RLS on Auction_results.
--  * Read-only: no changes to Auction_results or the scraper.
--  * Headline metrics use DEDICATED jewellery sales only (sale_scope =
--    'jewellery_sale'). Jewellery lots rescued from mixed / single-owner
--    sales are flagged separately (is_jewellery but scope <> dedicated) so
--    the page can offer them as an "include other sales" toggle.
--  * Cross-house values use buyer's total (sold_price) converted to USD at the
--    LATEST ECB reference rates (bard.fx_rates, refreshed daily in-database by
--    pg_cron). Every period is converted at the same current rate, so year-on-
--    year comparisons are constant-currency. Hammer is Bonhams-only.
--  * Market share and concentration are calculated on LIVE auctions only
--    (sale_format = 'live'), because BARD captures Bonhams' weekly/online
--    jewellery sales but mostly only flagship live sales for competitors.
-- =====================================================================

create schema if not exists bard;
revoke all on schema bard from anon, authenticated;

-- ---------------------------------------------------------------------
-- 1. FX — latest ECB reference rates, fetched daily inside the database.
--    Requires the http and pg_cron extensions (available on this project,
--    not yet enabled). Source: Frankfurter API (free, no key, ECB data).
-- ---------------------------------------------------------------------
create extension if not exists http    with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create table if not exists bard.fx_rates (
  rate_date   date        not null,
  currency    text        not null,
  usd_rate    numeric     not null,   -- USD per 1 unit of currency
  source      text        not null default 'ECB via Frankfurter',
  fetched_at  timestamptz not null default now(),
  primary key (rate_date, currency)
);

create or replace function bard.refresh_fx()
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  resp extensions.http_response;
  body jsonb;
begin
  resp := extensions.http_get(
    'https://api.frankfurter.dev/v1/latest?base=USD&symbols=GBP,EUR,CHF,HKD,AUD,CNY');
  if resp.status <> 200 then
    raise exception 'FX refresh failed: HTTP %', resp.status;
  end if;
  body := resp.content::jsonb;

  insert into bard.fx_rates (rate_date, currency, usd_rate)
  select (body->>'date')::date, r.key, round(1 / r.value::numeric, 6)
  from jsonb_each_text(body->'rates') r
  union all
  select (body->>'date')::date, 'USD', 1
  on conflict (rate_date, currency)
  do update set usd_rate = excluded.usd_rate, fetched_at = now();
end;
$fn$;

revoke all on function bard.refresh_fx() from public, anon, authenticated;

-- Seed now, then refresh daily after the ECB publishes (~16:00 CET)
select bard.refresh_fx();
select cron.schedule('bard-refresh-fx', '15 16 * * 1-5', 'select bard.refresh_fx()');

-- Latest rate per currency — every view converts through this
create or replace view bard.fx_v with (security_invoker = true) as
select distinct on (currency) currency, usd_rate, rate_date, source
from bard.fx_rates
order by currency, rate_date desc;

-- ---------------------------------------------------------------------
-- 2. Enriched lots — one row per lot, with classification, region, FY, USD.
--    Also the basis for in-page comps later.
-- ---------------------------------------------------------------------
create or replace view bard.lots_v with (security_invoker = true) as
with base as (
  select
    r.id, r.auction_house, r.auction_name, r.auction_number,
    cast(r.auction_date as date)                              as sale_date,
    r.lot_number, r.lot_title, r.lot_description, r.lot_url, r.image_url,
    r.currency, r.est_low, r.est_high, r.hammer_price, r.sold_price, r.status,

    -- Sale scope, from the sale name
    case
      when r.auction_name ~* 'jewel'
       and r.auction_name !~* 'watch|handbag|fashion|\mpens\M|wine'         then 'jewellery_sale'
      when r.auction_name ~* 'jewel'                                          then 'mixed_sale'
      when r.auction_name ~* 'watch|timepiece|horolog|clock|handbag|fashion|couture|chanel|herm[eè]s|dior|luxury|\mpens\M|writing|interiors|\mhome\M|wine|textile|punk|pop x|wardrobe|photograph'
                                                                              then 'non_jewellery_sale'
      else 'collection_sale'   -- single-owner / estate / themed sales
    end                                                       as sale_scope,

    -- Sale format: Bonhams runs ~60 weekly/online jewellery sales a year, while
    -- competitor coverage is mostly flagship live sales. Needed for like-for-like.
    case when r.auction_name ~* 'weekly|online' then 'online' else 'live' end
                                                              as sale_format,

    -- Lot class, from the lot title (used only outside dedicated sales)
    case
      when r.lot_title ~* '\m(wrist ?)?watch|chronograph|timepiece|\mclocks?\M'
       and r.lot_title !~* 'watch ?(chain|fob|key)'                           then 'watch'
      when r.lot_title ~* '\m(handbags?|bags?|birkin|kelly|clutch|tote|wallet|backpack|luggage|trunk|suitcase|pochette)\M'
                                                                              then 'bag'
      when r.lot_title ~* '\m(fountain pens?|pens?|pencils?|writing instruments?|ballpoint|rollerball)\M'
                                                                              then 'pen'
      when r.lot_title ~* '\m(print|vase|painting|drawing|photograph|lithograph)\M'
                                                                              then 'other'
      when r.lot_title ~* '\m(rings?|brooch(es)?|necklaces?|necklet|earrings?|ear ?clips|ear ?pendants|bracelets?|bangles?|pendants?|tiaras?|cufflinks|cuff links|parure|demi-parure|sautoir|chokers?|lockets?|jewel(le)?ry|jewels?|diadem)\M'
        or r.lot_title ~* '\m(diamonds?|sapphires?|rub(y|ies)|emeralds?|spinels?|pearls?|jadeite|opals?)\M'
                                                                              then 'jewellery'
      else 'other'
    end                                                       as lot_class,

    -- Region: sale-name city first, currency as fallback
    coalesce(
      case
        when r.auction_name ~* 'geneva|swiss|switzerland'                      then 'Switzerland'
        when r.auction_name ~* 'hong kong|shanghai|singapore'                 then 'Asia'
        when r.auction_name ~* 'sydney|melbourne|australia'                   then 'Australia'
        when r.auction_name ~* 'london|knightsbridge|edinburgh'               then 'UK'
        when r.auction_name ~* 'paris|monaco|milan'                           then 'Europe'
        when r.auction_name ~* 'new york|california|los angeles|\mla\M|miami|san francisco' then 'US'
      end,
      case r.currency
        when 'CHF' then 'Switzerland' when 'HKD' then 'Asia' when 'CNY' then 'Asia'
        when 'AUD' then 'Australia'   when 'GBP' then 'UK'   when 'EUR' then 'Europe'
        when 'USD' then 'US'
      end,
      'Unknown'
    )                                                         as region
  from public."Auction_results" r
)
select
  b.*,
  -- Fiscal year: July–June, labelled by the June year (FY26 = Jul 2025–Jun 2026)
  (extract(year from b.sale_date)::int
     + case when extract(month from b.sale_date) >= 7 then 1 else 0 end)  as fy,
  'FY' || lpad(((extract(year from b.sale_date)::int
     + case when extract(month from b.sale_date) >= 7 then 1 else 0 end) % 100)::text, 2, '0')
                                                                           as fy_label,
  date_trunc('month', b.sale_date)::date                                    as sale_month,

  (b.sale_scope = 'jewellery_sale'
   or (b.sale_scope in ('mixed_sale','collection_sale') and b.lot_class = 'jewellery'))
                                                                           as is_jewellery,

  case upper(b.status)
    when 'SOLD' then 'sold' when 'NOT_SOLD' then 'unsold' when 'UNSOLD' then 'unsold'
    else 'unknown'   -- Sotheby's has ~2.4k lots with no status
  end                                                                      as status_norm,
  upper(b.status) = 'SOLD'                                                 as is_sold,

  -- Item type, for estimate performance and comps filters
  case
    when b.lot_title ~* '\m(earrings?|ear ?clips|earclips|ear ?pendants)\M'   then 'Earrings'
    when b.lot_title ~* '\m(necklaces?|necklet|sautoir|chokers?|rivi[eè]re)\M' then 'Necklace'
    when b.lot_title ~* '\m(bracelets?|bangles?|cuffs?)\M'                   then 'Bracelet'
    when b.lot_title ~* '\mbrooch(es)?\M'                                    then 'Brooch'
    when b.lot_title ~* '\m(pendants?|lockets?)\M'                           then 'Pendant'
    when b.lot_title ~* '\mrings?\M'                                         then 'Ring'
    when b.lot_title ~* '\m(cufflinks|cuff links)\M'                         then 'Cufflinks'
    when b.lot_title ~* '\m(loose|unmounted|parcel)\M'                       then 'Loose stone'
    when b.lot_class = 'watch'                                               then 'Watch'
    else 'Other'
  end                                                                      as item_type,

  fx.usd_rate,
  round(b.sold_price   * fx.usd_rate, 0)                                   as sold_usd,
  round(b.hammer_price * fx.usd_rate, 0)                                   as hammer_usd,

  -- Estimate band vs hammer (meaningful for Bonhams only; others lack hammer)
  case
    when b.hammer_price is null or upper(b.status) <> 'SOLD'               then null
    when b.est_low is null or b.est_high is null                           then 'No estimate'
    when b.hammer_price <  b.est_low                                       then 'Below'
    when b.hammer_price >  b.est_high                                      then 'Above'
    else 'Within'
  end                                                                      as estimate_band
from base b
left join bard.fx_v fx on fx.currency = b.currency;

-- ---------------------------------------------------------------------
-- 3. Monthly facts — the page derives FY, YTD, share and sell-through from this.
-- ---------------------------------------------------------------------
create or replace view bard.monthly_v with (security_invoker = true) as
select
  auction_house, region, sale_month, fy, fy_label, sale_format,
  (sale_scope = 'jewellery_sale')                           as dedicated,
  count(distinct auction_name || '|' || sale_date)          as sales,
  count(*)                                                  as lots_offered,
  count(*) filter (where status_norm = 'sold')              as lots_sold,
  count(*) filter (where status_norm = 'unsold')            as lots_unsold,
  count(*) filter (where status_norm = 'unknown')           as lots_status_unknown,
  coalesce(sum(sold_usd)   filter (where is_sold), 0)       as sold_usd,
  sum(hammer_usd)          filter (where is_sold)           as hammer_usd,
  count(*) filter (where is_sold and sold_usd is null)      as sold_lots_missing_value
from bard.lots_v
where is_jewellery
group by 1,2,3,4,5,6,7;

-- ---------------------------------------------------------------------
-- 4. Concentration — how much of each house's FY value sits in its top lots.
--    Dedicated jewellery sales, LIVE auctions only, sold lots with a value.
-- ---------------------------------------------------------------------
create or replace view bard.concentration_v with (security_invoker = true) as
with ranked as (
  select auction_house, fy, fy_label, sold_usd, lot_title, lot_url,
         row_number() over (partition by auction_house, fy order by sold_usd desc) as rn,
         count(*)     over (partition by auction_house, fy)                        as n,
         sum(sold_usd) over (partition by auction_house, fy)                       as total_usd
  from bard.lots_v
  where is_sold and sale_scope = 'jewellery_sale' and sale_format = 'live'
    and sold_usd is not null
)
select
  auction_house, fy, fy_label,
  max(n)                                                                   as lots_sold,
  max(total_usd)                                                           as total_usd,
  round(sum(sold_usd) filter (where rn <= ceil(n * 0.10)) / max(total_usd), 4) as top10pct_share,
  round(sum(sold_usd) filter (where rn <= ceil(n * 0.05)) / max(total_usd), 4) as top5pct_share,
  round(max(sold_usd) / max(total_usd), 4)                                 as top_lot_share,
  max(lot_title) filter (where rn = 1)                                     as top_lot_title,
  max(lot_url)   filter (where rn = 1)                                     as top_lot_url,
  max(sold_usd)                                                            as top_lot_usd
from ranked
group by 1,2,3;

-- ---------------------------------------------------------------------
-- 5. Estimate performance — Bonhams only (hammer needed), dedicated sales.
-- ---------------------------------------------------------------------
create or replace view bard.estimate_perf_v with (security_invoker = true) as
select
  fy, fy_label, region, item_type, sale_format,
  count(*)                                                    as lots,
  count(*) filter (where estimate_band = 'Below')             as below_est,
  count(*) filter (where estimate_band = 'Within')            as within_est,
  count(*) filter (where estimate_band = 'Above')             as above_est,
  round(percentile_cont(0.5) within group (order by hammer_price / nullif(est_low, 0))::numeric, 3)
                                                              as median_hammer_to_low_est
from bard.lots_v
where auction_house = 'Bonhams' and sale_scope = 'jewellery_sale'
  and is_sold and estimate_band in ('Below','Within','Above')
group by 1,2,3,4,5;

-- ---------------------------------------------------------------------
-- 6. Recent notable lots — top 15 per house from the last 180 days.
-- ---------------------------------------------------------------------
create or replace view bard.recent_top_lots_v with (security_invoker = true) as
select * from (
  select
    auction_house, auction_name, sale_date, sale_format, region, item_type,
    lot_number, lot_title, currency, est_low, est_high, hammer_price, sold_price, sold_usd,
    estimate_band, lot_url, image_url,
    row_number() over (partition by auction_house order by sold_usd desc) as house_rank
  from bard.lots_v
  where is_jewellery and is_sold and sold_usd is not null
    and sale_date >= current_date - 180
) t
where house_rank <= 15;

-- ---------------------------------------------------------------------
-- 7. Meta — freshness, coverage and per-house caveats for the page header.
--    No scrape timestamp exists yet, so "latest sale captured" is the proxy.
--    Caveats are data-driven, so they clear themselves if the data improves.
-- ---------------------------------------------------------------------
create or replace view bard.meta_v with (security_invoker = true) as
with h as (
  select
    auction_house,
    count(*)                                                        as total_rows,
    count(*) filter (where is_jewellery)                            as jewellery_lots,
    count(distinct auction_name || '|' || sale_date)
          filter (where sale_scope = 'jewellery_sale')              as dedicated_sales,
    count(distinct auction_name || '|' || sale_date)
          filter (where sale_scope = 'jewellery_sale' and sale_format = 'live')
                                                                    as dedicated_live_sales,
    min(sale_date) filter (where is_jewellery)                      as first_sale_date,
    max(sale_date) filter (where is_jewellery)                      as latest_sale_date,
    count(*) filter (where is_jewellery and status_norm = 'unknown') as status_unknown_lots,
    count(hammer_price) filter (where is_jewellery and is_sold)     as lots_with_hammer
  from bard.lots_v
  group by 1
)
select
  h.*,
  (h.status_unknown_lots::numeric / nullif(h.jewellery_lots, 0)) < 0.02
                                                                    as sell_through_reliable,
  nullif(concat_ws(' ',
    case when (h.status_unknown_lots::numeric / nullif(h.jewellery_lots, 0)) >= 0.02
         then format('%s lots have no sold/unsold status, so sell-through is not reported and lot counts are indicative.',
                     to_char(h.status_unknown_lots, 'FM999,999')) end,
    case when h.lots_with_hammer = 0
         then 'No hammer prices captured; values are buyer''s total.' end,
    case when h.latest_sale_date < current_date - 60
         then format('No sales captured since %s.', to_char(h.latest_sale_date, 'DD Mon YYYY')) end
  ), '')                                                            as caveat,
  (select max(rate_date) from bard.fx_rates)                        as fx_rate_date,
  now()                                                             as generated_at,
  'Buyer''s total in USD at latest ECB rates; share and concentration on live auctions only'
                                                                    as value_basis
from h;

revoke all on all tables in schema bard from anon, authenticated;
revoke all on all functions in schema bard from public, anon, authenticated;
