/*
   Monthly Transaction Growth Analysis
   This query calculates the month-over-month (MoM) percentage change in 
   approved transactions per country.
 */

WITH monthly_counts AS (
  -- Aggregate base transaction volumes by country and month
  SELECT 
    u.country,
    DATE_TRUNC('MONTH', t.ts_created_at) AS month, 
    COUNT(t.transaction_id) AS number_of_txns
  FROM silver_transactions t
  LEFT JOIN silver_users u 
    USING (user_id)
  WHERE t.status = 'APPROVED' --excludes DECLINED transactions 
    -- Excludes current incomplete year to avoid skewed results; in moving into a view I would consider paramemetizing the date range
    AND DATE_TRUNC('MONTH', t.ts_created_at) < '2026-01-01' 
  GROUP BY 
    u.country,
    DATE_TRUNC('MONTH', t.ts_created_at)
),

counts_with_lag AS (
  --Used LAG window function to capture the previous month's volume for comparison
  SELECT 
    country,
    month,
    number_of_txns,
    LAG(number_of_txns, 1) OVER (
      PARTITION BY country 
      ORDER BY month
    ) AS number_of_txns_prev_month
  FROM monthly_counts
)

-- Final MoM metrics
SELECT 
  country,
  month,
  number_of_txns,
  number_of_txns_prev_month,
  -- Used NULLIF to handle potential division by zero on the first month for a country
  ROUND(
    (
      (number_of_txns - number_of_txns_prev_month) / 
      NULLIF(number_of_txns_prev_month, 0)
    ) * 100, 
    2
  ) AS change_in_txns_percentage
FROM counts_with_lag
ORDER BY 
  month ASC, 
  country ASC;












