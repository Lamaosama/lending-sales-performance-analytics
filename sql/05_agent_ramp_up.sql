-- 05. New-agent ramp-up: disbursed loans per active agent-day by tenure month
-- Shows how long it takes a newly hired agent to reach full productivity.

WITH agent_days AS (
    SELECT
        a.agent_id,
        a.application_date,
        CAST((JULIANDAY(a.application_date) - JULIANDAY(g.hire_date)) / 30 AS INTEGER) AS tenure_month,
        SUM(a.is_disbursed) AS disbursed_loans
    FROM applications a
    JOIN agents g USING (agent_id)
    GROUP BY a.agent_id, a.application_date
)
SELECT
    CASE WHEN tenure_month >= 6 THEN '6+' ELSE CAST(tenure_month AS TEXT) END AS tenure_month,
    COUNT(DISTINCT agent_id)                    AS agents,
    COUNT(*)                                    AS active_agent_days,
    ROUND(1.0 * SUM(disbursed_loans) / COUNT(*), 2) AS loans_per_active_day
FROM agent_days
GROUP BY 1
ORDER BY MIN(tenure_month);
