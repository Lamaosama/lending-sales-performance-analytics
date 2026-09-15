-- 03. Location scorecard (whole period)
-- One row per location with funnel KPIs, target achievement and agent productivity.
-- Achievement rank uses a window function so managers can sort the network.

WITH loc AS (
    SELECT
        a.location_id,
        COUNT(*)                         AS applications,
        SUM(a.decision = 'Approved')     AS approved,
        SUM(a.is_disbursed)              AS disbursed_loans,
        SUM(a.disbursed_amount_egp)      AS disbursed_egp,
        COUNT(DISTINCT a.agent_id)       AS agents
    FROM applications a
    GROUP BY a.location_id
),
tgt AS (
    SELECT location_id, SUM(disbursement_target_egp) AS target_egp
    FROM targets
    GROUP BY location_id
)
SELECT
    l.location_id,
    l.region,
    l.location_type,
    loc.agents,
    loc.applications,
    ROUND(100.0 * loc.approved / loc.applications, 1)          AS approval_rate_pct,
    ROUND(100.0 * loc.disbursed_loans / loc.approved, 1)       AS approved_to_disbursed_pct,
    ROUND(loc.disbursed_egp / 1e6, 2)                          AS disbursed_egp_m,
    ROUND(tgt.target_egp / 1e6, 2)                             AS target_egp_m,
    ROUND(100.0 * loc.disbursed_egp / tgt.target_egp, 1)       AS achievement_pct,
    ROUND(1.0 * loc.disbursed_loans / loc.agents / 6, 1)       AS loans_per_agent_month,
    RANK() OVER (ORDER BY loc.disbursed_egp / tgt.target_egp DESC) AS achievement_rank
FROM loc
JOIN locations l USING (location_id)
JOIN tgt        USING (location_id)
ORDER BY achievement_rank;
