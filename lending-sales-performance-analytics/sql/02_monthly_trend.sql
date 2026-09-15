-- 02. Monthly trend with target achievement and month-over-month growth

WITH monthly AS (
    SELECT
        SUBSTR(application_date, 1, 7)          AS month,
        COUNT(*)                                AS applications,
        SUM(decision = 'Approved')              AS approved,
        SUM(is_disbursed)                       AS disbursed_loans,
        SUM(disbursed_amount_egp)               AS disbursed_egp,
        COUNT(DISTINCT agent_id)                AS active_agents
    FROM applications
    GROUP BY 1
),
monthly_target AS (
    SELECT month, SUM(disbursement_target_egp) AS target_egp
    FROM targets
    GROUP BY 1
)
SELECT
    m.month,
    m.applications,
    ROUND(100.0 * m.approved / m.applications, 1)              AS approval_rate_pct,
    ROUND(m.disbursed_egp / 1e6, 1)                            AS disbursed_egp_m,
    ROUND(t.target_egp / 1e6, 1)                               AS target_egp_m,
    ROUND(100.0 * m.disbursed_egp / t.target_egp, 1)           AS achievement_pct,
    ROUND(1.0 * m.disbursed_loans / m.active_agents, 1)        AS loans_per_agent,
    ROUND(100.0 * (m.disbursed_egp - LAG(m.disbursed_egp) OVER (ORDER BY m.month))
          / LAG(m.disbursed_egp) OVER (ORDER BY m.month), 1)   AS mom_growth_pct
FROM monthly m
JOIN monthly_target t USING (month)
ORDER BY m.month;
