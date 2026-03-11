/* Monthly "North Star" Metrics: Slicing Revenue, Risk, and Speed.
   
    Business Logic:
    1. TTV: Time from 'App Open' to 'First Transaction' (The full user journey).
    2. FX Normalization: Standardized to USD based on Feb 2026 estimates.
    3. Dimensions: Marketing Source and Country for acquisition performance analysis.
*/ 

CREATE OR REPLACE TABLE gold_fact_financials_monthly AS 

WITH user_journey_milestones AS (
    -- 1. Get the Anchor Dates (App Open & Activation) per user
    -- Groups by user_id to ensure 1 row per user before joining transactions
    SELECT 
        u.user_id,
        u.country,
        u.marketing_source,
        MIN(CASE WHEN e.event_name = 'app_open' THEN e.event_timestamp END) AS first_app_open_ts,
        MIN(CASE WHEN e.event_name = 'account_activated' THEN e.event_timestamp END) AS activation_ts
    FROM silver_users u
    LEFT JOIN silver_events e ON u.user_id = e.user_id
    GROUP BY 1, 2, 3
),

user_first_transaction AS (
    -- 2. Identify the very first time a user successfully spent money
    -- This is essential for calculating the true Time-To-Value (TTV)
    SELECT 
        user_id,
        MIN(ts_created_at) AS global_first_spend_ts
    FROM silver_transactions 
    WHERE status = 'APPROVED'
    GROUP BY 1
),

monthly_activity AS (
    -- 3. Aggregate Monthly Transaction Volume
    SELECT 
        DATE_TRUNC('MONTH', t.ts_created_at) AS month,
        t.user_id,
        SUM(t.amount) AS local_tpv,
        COUNT(t.transaction_id) AS approved_count
    FROM silver_transactions t
    WHERE t.status = 'APPROVED'
    GROUP BY 1, 2
),

enriched_financials AS (
    -- 4. Putting it all together: Financials + User Context + FX Rates
    SELECT 
        m.month,
        u.country,
        u.marketing_source,
        m.user_id,
        m.local_tpv,
        m.approved_count,
        
        -- Logic: Is this the month they were acquired? 
        CASE 
            WHEN DATE_TRUNC('MONTH', u.activation_ts) = m.month THEN 1 
            ELSE 0 
        END AS is_new_user,

        -- TTV Calculation: First Spend - First App Open (In Hours)
        (unix_timestamp(ft.global_first_spend_ts) - unix_timestamp(u.first_app_open_ts)) / 3600 AS user_ttv_hours,

        -- FX Normalization (USD conversion based on Feb 2026 rates)
        CASE 
            WHEN u.country = 'Colombia' THEN (m.local_tpv * 0.00025)
            WHEN u.country = 'Mexico'   THEN (m.local_tpv * 0.055)
            WHEN u.country = 'Brazil'   THEN (m.local_tpv * 0.18)
            ELSE 0 
        END AS tpv_usd,
        
        -- Revenue Estimation (Interchange Fee Logic prevalent in LATAM)
        CASE 
            WHEN u.country = 'Colombia' THEN (m.local_tpv * 0.00025) * 0.005  -- 0.50%
            WHEN u.country = 'Mexico'   THEN (m.local_tpv * 0.055)   * 0.0115 -- 1.15%
            WHEN u.country = 'Brazil'   THEN (m.local_tpv * 0.18)    * 0.007  -- 0.70%
            ELSE 0 
        END AS revenue_usd

    FROM monthly_activity m
    INNER JOIN user_journey_milestones u ON m.user_id = u.user_id
    LEFT JOIN user_first_transaction ft ON m.user_id = ft.user_id
)

-- 5. Final Gold Table Output
SELECT 
    month,
    country,
    marketing_source, 
    
    -- Financial Core
    ROUND(SUM(tpv_usd), 2) AS total_payment_volume_usd,
    ROUND(SUM(revenue_usd), 2) AS gross_revenue_usd,
    COUNT(DISTINCT user_id) AS active_paying_users,
    
    -- Growth Insight: Revenue split (New vs. Existing)
    ROUND(SUM(CASE WHEN is_new_user = 1 THEN revenue_usd ELSE 0 END), 2) AS revenue_from_new_users_usd,
    
    -- Unit Economics
    ROUND(SUM(revenue_usd) / NULLIF(COUNT(DISTINCT user_id), 0), 2) AS ARPAC_usd,
    
    -- Speed Insight: Average TTV
    ROUND(AVG(user_ttv_hours), 1) AS avg_time_to_value_hours,
    
    -- Efficiency Insight: Take Rate
    ROUND((SUM(revenue_usd) / NULLIF(SUM(tpv_usd), 0)) * 100, 3) AS take_rate_pct

FROM enriched_financials
GROUP BY 1, 2, 3
ORDER BY month ASC;
