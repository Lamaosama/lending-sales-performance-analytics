-- 04. Performance by product and by region

-- 4a. Product performance
SELECT
    p.product_name,
    COUNT(*)                                                   AS applications,
    ROUND(100.0 * SUM(a.decision = 'Approved') / COUNT(*), 1)  AS approval_rate_pct,
    ROUND(SUM(a.disbursed_amount_egp) / 1e6, 1)                AS disbursed_egp_m,
    ROUND(100.0 * SUM(a.disbursed_amount_egp)
          / SUM(SUM(a.disbursed_amount_egp)) OVER (), 1)       AS share_of_disbursement_pct,
    ROUND(SUM(a.disbursed_amount_egp) / SUM(a.is_disbursed), 0) AS avg_ticket_egp
FROM applications a
JOIN products p USING (product_id)
GROUP BY p.product_name
ORDER BY disbursed_egp_m DESC;

-- 4b. Region performance vs target
WITH r AS (
    SELECT l.region,
           COUNT(*)                        AS applications,
           SUM(a.decision = 'Approved')    AS approved,
           SUM(a.disbursed_amount_egp)     AS disbursed_egp
    FROM applications a
    JOIN locations l USING (location_id)
    GROUP BY l.region
),
t AS (
    SELECT l.region, SUM(t.disbursement_target_egp) AS target_egp
    FROM targets t
    JOIN locations l USING (location_id)
    GROUP BY l.region
)
SELECT
    r.region,
    r.applications,
    ROUND(100.0 * r.approved / r.applications, 1)     AS approval_rate_pct,
    ROUND(r.disbursed_egp / 1e6, 1)                   AS disbursed_egp_m,
    ROUND(100.0 * r.disbursed_egp / t.target_egp, 1)  AS achievement_pct
FROM r
JOIN t USING (region)
ORDER BY achievement_pct DESC;
