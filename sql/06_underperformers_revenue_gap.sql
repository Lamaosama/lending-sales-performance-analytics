-- 06. Underperforming locations, root-cause flag and revenue gap
-- Underperforming = below 85% of target over the period.
-- Root cause compares each location with the network benchmark:
--   * Low approval         -> approval rate 10+ pts below network
--   * Disbursement leakage -> approved-to-disbursed 10+ pts below network
--   * Low volume           -> funnel is healthy, not enough applications

WITH loc AS (
    SELECT
        location_id,
        COUNT(*)                                             AS applications,
        1.0 * SUM(decision = 'Approved') / COUNT(*)          AS approval_rate,
        1.0 * SUM(is_disbursed) / SUM(decision = 'Approved') AS disb_rate,
        SUM(disbursed_amount_egp)                            AS disbursed_egp
    FROM applications
    GROUP BY location_id
),
network AS (
    SELECT
        1.0 * SUM(decision = 'Approved') / COUNT(*)          AS approval_rate,
        1.0 * SUM(is_disbursed) / SUM(decision = 'Approved') AS disb_rate
    FROM applications
),
tgt AS (
    SELECT location_id, SUM(disbursement_target_egp) AS target_egp
    FROM targets
    GROUP BY location_id
),
flagged AS (
    SELECT
        loc.location_id,
        l.region,
        l.location_type,
        loc.applications,
        ROUND(100 * loc.approval_rate, 1)                 AS approval_rate_pct,
        ROUND(100 * loc.disb_rate, 1)                     AS approved_to_disbursed_pct,
        ROUND(100.0 * loc.disbursed_egp / tgt.target_egp, 1) AS achievement_pct,
        ROUND((tgt.target_egp - loc.disbursed_egp) / 1e6, 2) AS gap_to_target_egp_m,
        CASE
            WHEN loc.approval_rate < n.approval_rate - 0.10 THEN 'Low approval'
            WHEN loc.disb_rate     < n.disb_rate     - 0.10 THEN 'Disbursement leakage'
            ELSE 'Low volume'
        END AS root_cause
    FROM loc
    CROSS JOIN network n
    JOIN tgt       USING (location_id)
    JOIN locations l USING (location_id)
    WHERE ROUND(100.0 * loc.disbursed_egp / tgt.target_egp, 1) < 85
)
SELECT *
FROM flagged
ORDER BY gap_to_target_egp_m DESC;
