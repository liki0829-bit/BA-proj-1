-- 02_analysis_queries.sql : business questions answered with SQL (SQLite dialect)
-- Each query is tagged with "-- Q<n>" so build_db.py can run and export them.

-- =====================================================================
-- Q1. Which PRODUCT has the highest defects?  (count AND rate)
-- Why both? Raw counts favour high-volume products; the rate shows true quality.
-- =====================================================================
-- Q1
SELECT  p.product_id,
        p.product_name,
        SUM(pl.units_produced)                                         AS units_produced,
        SUM(pl.units_defective)                                        AS units_defective,
        ROUND(100.0 * SUM(pl.units_defective) / SUM(pl.units_produced), 2) AS defect_rate_pct
FROM    production_log pl
JOIN    products p ON p.product_id = pl.product_id
GROUP BY p.product_id, p.product_name
ORDER BY defect_rate_pct DESC;

-- =====================================================================
-- Q2. Which MONTH had the highest downtime?
-- =====================================================================
-- Q2
SELECT  strftime('%Y-%m', event_date)            AS month,
        COUNT(*)                                 AS downtime_events,
        SUM(duration_minutes)                    AS total_downtime_min,
        ROUND(SUM(duration_minutes) / 60.0, 1)   AS total_downtime_hours
FROM    downtime_events
GROUP BY month
ORDER BY total_downtime_min DESC;

-- =====================================================================
-- Q3. Which MACHINE needs investigation?
-- Approach: combine defect rate and downtime, compare each machine with the
-- plant average, and flag machines that are worse than average on BOTH.
-- =====================================================================
-- Q3
WITH quality AS (
    SELECT machine_id,
           SUM(units_produced)  AS units,
           SUM(units_defective) AS defects,
           100.0 * SUM(units_defective) / SUM(units_produced) AS defect_rate_pct
    FROM production_log
    GROUP BY machine_id
),
downtime AS (
    SELECT machine_id,
           COUNT(*)              AS events,
           SUM(duration_minutes) AS downtime_min
    FROM downtime_events
    GROUP BY machine_id
),
combined AS (
    SELECT m.machine_id, m.line_id, m.machine_type,
           q.defect_rate_pct,
           COALESCE(d.events, 0)       AS downtime_events,
           COALESCE(d.downtime_min, 0) AS downtime_min
    FROM machines m
    JOIN quality q        ON q.machine_id = m.machine_id
    LEFT JOIN downtime d  ON d.machine_id = m.machine_id
)
SELECT  machine_id, line_id, machine_type,
        ROUND(defect_rate_pct, 2)                                     AS defect_rate_pct,
        downtime_events,
        downtime_min,
        ROUND(defect_rate_pct / (SELECT AVG(defect_rate_pct) FROM combined), 2) AS defect_vs_avg_x,
        ROUND(1.0 * downtime_min / (SELECT AVG(downtime_min) FROM combined), 2) AS downtime_vs_avg_x,
        CASE WHEN defect_rate_pct > (SELECT AVG(defect_rate_pct) FROM combined)
              AND downtime_min    > (SELECT AVG(downtime_min)    FROM combined)
             THEN 'INVESTIGATE' ELSE 'ok' END                         AS status
FROM    combined
ORDER BY defect_vs_avg_x + downtime_vs_avg_x DESC;

-- =====================================================================
-- Q4. Defect rate trend by LINE, with month-over-month change (window function)
-- =====================================================================
-- Q4
WITH monthly AS (
    SELECT  m.line_id,
            strftime('%Y-%m', pl.production_date)                               AS month,
            100.0 * SUM(pl.units_defective) / SUM(pl.units_produced)            AS defect_rate_pct
    FROM    production_log pl
    JOIN    machines m ON m.machine_id = pl.machine_id
    GROUP BY m.line_id, month
)
SELECT  line_id, month,
        ROUND(defect_rate_pct, 2)                                                AS defect_rate_pct,
        ROUND(defect_rate_pct - LAG(defect_rate_pct) OVER (PARTITION BY line_id ORDER BY month), 2)
                                                                                 AS mom_change_pts
FROM    monthly
WHERE   line_id = 'C'
ORDER BY month;

-- =====================================================================
-- Q5. Why is the flagged machine down?  Pareto of downtime reasons (C-02)
-- =====================================================================
-- Q5
WITH reasons AS (
    SELECT reason,
           COUNT(*)              AS events,
           SUM(duration_minutes) AS minutes
    FROM   downtime_events
    WHERE  machine_id = 'C-02'
    GROUP BY reason
)
SELECT  reason, events, minutes,
        ROUND(100.0 * minutes / SUM(minutes) OVER (), 1)                          AS pct_of_total,
        ROUND(100.0 * SUM(minutes) OVER (ORDER BY minutes DESC
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                     / SUM(minutes) OVER (), 1)                                   AS cumulative_pct
FROM    reasons
ORDER BY minutes DESC;

-- =====================================================================
-- Q6. Does downtime go hand in hand with defects?  Monthly view for machine C-02
-- =====================================================================
-- Q6
WITH q AS (
    SELECT strftime('%Y-%m', production_date) AS month,
           ROUND(100.0 * SUM(units_defective) / SUM(units_produced), 2) AS defect_rate_pct
    FROM production_log WHERE machine_id = 'C-02' GROUP BY month
),
d AS (
    SELECT strftime('%Y-%m', event_date) AS month,
           SUM(duration_minutes) AS downtime_min
    FROM downtime_events WHERE machine_id = 'C-02' GROUP BY month
)
SELECT q.month, q.defect_rate_pct, COALESCE(d.downtime_min, 0) AS downtime_min
FROM   q LEFT JOIN d ON d.month = q.month
ORDER BY q.month;

-- =====================================================================
-- Q7. Inventory risk: product-months at or below 125% of the reorder point
-- =====================================================================
-- Q7
SELECT  p.product_name,
        i.month,
        i.on_hand_units,
        i.reorder_point,
        ROUND(100.0 * i.on_hand_units / i.reorder_point, 0) AS pct_of_reorder_point,
        CASE WHEN i.on_hand_units < i.reorder_point THEN 'BELOW REORDER POINT'
             ELSE 'watch' END                               AS status
FROM    inventory_monthly i
JOIN    products p ON p.product_id = i.product_id
WHERE   i.on_hand_units <= 1.25 * i.reorder_point
ORDER BY i.month, pct_of_reorder_point;
