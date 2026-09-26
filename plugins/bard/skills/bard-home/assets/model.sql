with l as (select * from bard.lots_v where is_jewellery and sale_scope = 'jewellery_sale'),
cur as (
  select fy as cfy, current_date - make_date(fy - 1, 7, 1) as fy_day
  from (select extract(year from current_date)::int + case when extract(month from current_date) >= 7 then 1 else 0 end as fy) x
),
fy_tot as (
  select auction_house h, fy, sale_format f,
    count(distinct auction_name || '|' || sale_date) sales, count(*) offered,
    count(*) filter (where status_norm = 'sold') sold,
    count(*) filter (where status_norm = 'unknown') unk,
    coalesce(round(sum(sold_usd) filter (where is_sold)), 0) usd
  from l where fy between (select cfy from cur) - 3 and (select cfy from cur) group by 1,2,3),
reg as (
  select auction_house h, fy, region r,
    count(distinct auction_name || '|' || sale_date) sales,
    count(*) filter (where status_norm = 'sold') sold,
    coalesce(round(sum(sold_usd) filter (where is_sold)), 0) usd
  from l where sale_format = 'live' and fy between (select cfy from cur) - 3 and (select cfy from cur) group by 1,2,3),
ytd as (
  select auction_house h, sale_format f,
    coalesce(round(sum(sold_usd) filter (where is_sold and fy = cfy)), 0) cur_usd,
    coalesce(round(sum(sold_usd) filter (where is_sold and fy = cfy - 1)), 0) prev_usd,
    count(*) filter (where status_norm = 'sold' and fy = cfy) cur_sold,
    count(*) filter (where status_norm = 'sold' and fy = cfy - 1) prev_sold,
    count(distinct auction_name || '|' || sale_date) filter (where fy = cfy) cur_sales,
    count(distinct auction_name || '|' || sale_date) filter (where fy = cfy - 1) prev_sales
  from l cross join cur
  where fy in (cfy, cfy - 1) and sale_date - make_date(fy - 1, 7, 1) <= fy_day
  group by 1,2),
trend as (
  select auction_house h, to_char(sale_month, 'YYYY-MM') m, round(sum(sold_usd) filter (where is_sold)) usd
  from l where sale_format = 'live' and sale_month >= date_trunc('month', current_date) - interval '23 months'
  group by 1,2),
est as (
  select fy, item_type t, count(*) n,
    count(*) filter (where estimate_band = 'Below') b,
    count(*) filter (where estimate_band = 'Within') w,
    count(*) filter (where estimate_band = 'Above') a,
    round(percentile_cont(0.5) within group (order by hammer_price / nullif(est_low, 0))::numeric, 2) med
  from l where auction_house = 'Bonhams' and is_sold and estimate_band in ('Below','Within','Above')
    and fy between (select cfy from cur) - 2 and (select cfy from cur)
  group by 1,2),
rec as (
  select * from (
    select auction_house h, auction_name s, sale_date d, sale_format f, region r, item_type t,
      left(lot_title, 120) title, currency c, est_low el, est_high eh, hammer_price hp, sold_price sp,
      sold_usd u, estimate_band band, lot_url url,
      row_number() over (partition by auction_house order by sold_usd desc) rn
    from l where is_sold and sold_usd is not null and sale_date >= current_date - 180) z
  where rn <= 6)
select json_build_object(
  'v', 1,
  'generated_at', now(),
  'cur_fy', (select cfy from cur),
  'fy_day', (select fy_day from cur),
  'fx', (select json_agg(json_build_array(currency, usd_rate, rate_date) order by currency) from bard.fx_v),
  'meta', (select json_agg(json_build_array(auction_house, latest_sale_date, sell_through_reliable, caveat, dedicated_live_sales) order by auction_house) from bard.meta_v),
  'fy', (select json_agg(json_build_array(h, fy, f, sales, offered, sold, unk, usd) order by h, fy, f) from fy_tot),
  'reg', (select json_agg(json_build_array(h, fy, r, sales, sold, usd) order by h, fy, r) from reg),
  'ytd', (select json_agg(json_build_array(h, f, cur_usd, prev_usd, cur_sold, prev_sold, cur_sales, prev_sales) order by h, f) from ytd),
  'trend', (select json_agg(json_build_array(h, m, usd) order by h, m) from trend),
  'conc', (select json_agg(json_build_array(auction_house, fy, lots_sold, round(total_usd), top10pct_share, top5pct_share, top_lot_share, left(top_lot_title, 100), top_lot_url, round(top_lot_usd)) order by auction_house, fy)
           from bard.concentration_v where fy between (select cfy from cur) - 3 and (select cfy from cur) - 1),
  'est', (select json_agg(json_build_array(fy, t, n, b, w, a, med) order by fy, n desc) from est),
  'recent', (select json_agg(json_build_array(h, s, d, f, r, t, title, c, el, eh, hp, sp, u, band, url) order by u desc) from rec)
) as model
