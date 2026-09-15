-- 01. Network KPI overview (whole period)
-- Funnel: applications -> approved -> disbursed

SELECT
    COUNT(*)                                                        AS applications,
    SUM(decision = 'Approved')                                      AS approved,
    SUM(is_disbursed)                                               AS disbursed_loans,
    ROUND(100.0 * SUM(decision = 'Approved') / COUNT(*), 1)         AS approval_rate_pct,
    ROUND(100.0 * SUM(is_disbursed) / SUM(decision = 'Approved'), 1) AS approved_to_disbursed_pct,
    ROUND(SUM(disbursed_amount_egp) / 1e6, 1)                       AS disbursed_egp_m,
    ROUND(SUM(disbursed_amount_egp) / SUM(is_disbursed), 0)         AS avg_ticket_egp,
    COUNT(DISTINCT location_id)                                     AS active_locations,
    COUNT(DISTINCT agent_id)                                        AS active_agents
FROM applications;
