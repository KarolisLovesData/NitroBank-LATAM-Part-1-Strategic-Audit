/**
 * MONTHLY "NORTH STAR" FINANCIALS FACT TABLE
 * PURPOSE: Aggregates revenue, unit economics, and user velocity into a BI-ready view.
 * 
 * PORTFOLIO NOTES:
 * - FX RATES: Hardcoded to Feb 2026 estimates for demonstration. Production would use a daily 'silver_fx_rates' dimension.
 * - TIMEZONES: Stored in UTC. Production localization (e.g., America/Bogota) would be applied for precise daily/monthly cutoffs.
 */

CREATE OR REPLACE TABLE gold_fact_financials_monthly AS 

WITH filtered_events AS (
    -- Extract crucial funnel timestamps for velocity tracking
    SELECT 
        user_id,
        MIN(CASE WHEN event_name = 'app_open' THEN event_timestamp END) AS first_app_open_ts,
        MIN(CASE WHEN event_name = 'account_activated' THEN event_timestamp END) AS activation_ts
    FROM silver_events
    WHERE event_name IN ('app_open', 'account_activated') 
    GROUP BY 1
),

user_journey_milestones AS (
    -- Consolidate core user dimensions and acquisition timelines
    SELECT 
        u.user_id,
        u.country,
        u.marketing_source,
        e.first_app_open_ts,
        e.activation_ts
    FROM silver_users u
    LEFT JOIN filtered_events e ON u.user_id = e.user_id
),

user_first_transaction AS (
    -- Isolate global first-spend to anchor the true Time-To-Value (TTV)
    SELECT 
        user_id,
        MIN(ts_created_at) AS global_first_spend_ts 
    FROM silver_transactions 
    WHERE status = 'APPROVED'
    GROUP BY 1
),

monthly_activity AS (
    -- Aggregate gross transaction behavior per user, per month
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
    -- Merge financials with cohort dimensions, apply FX logic, and estimate revenue
    SELECT 
        m.month,
        u.country,
        u.marketing_source,
        m.user_id,
        m.local_tpv,
        m.approved_count,
        
        -- Cohort Flagging: Did the user activate in this current billing month?
        CASE 
            WHEN DATE_TRUNC('MONTH', u.activation_ts) = m.month THEN 1 
            ELSE 0 
        END AS is_new_user,

        -- Velocity: Total hours from initial app open to first approved transaction
        (unix_timestamp(ft.global_first_spend_ts) - unix_timestamp(u.first_app_open_ts)) / 3600 AS user_ttv_hours,

        -- FX Normalization: Standardizing local volume to USD
        CASE 
            WHEN u.country = 'Colombia' THEN (m.local_tpv * 0.00025)
            WHEN u.country = 'Mexico'   THEN (m.local_tpv * 0.055)
            WHEN u.country = 'Brazil'   THEN (m.local_tpv * 0.18)
            ELSE 0 
        END AS tpv_usd,
        
        -- Yield Estimation: Applying regional interchange fee models
        CASE 
            WHEN u.country = 'Colombia' THEN (m.local_tpv * 0.00025) * 0.005  
            WHEN u.country = 'Mexico'   THEN (m.local_tpv * 0.055)   * 0.0115 
            WHEN u.country = 'Brazil'   THEN (m.local_tpv * 0.18)    * 0.007  
            ELSE 0 
        END AS revenue_usd

    FROM monthly_activity m
    INNER JOIN user_journey_milestones u ON m.user_id = u.user_id  
    LEFT JOIN user_first_transaction ft ON m.user_id = ft.user_id  
)

-- Final Aggregation: Roll up into executive "North Star" metrics
SELECT 
    month,
    country,
    marketing_source, 
    is_new_user,
    
    -- Financial Core
    ROUND(SUM(tpv_usd), 2) AS total_payment_volume_usd,
    ROUND(SUM(revenue_usd), 2) AS gross_revenue_usd,
    COUNT(DISTINCT user_id) AS active_paying_users,
    
    -- Unit Economics (ARPU)
    ROUND(SUM(revenue_usd) / NULLIF(COUNT(DISTINCT user_id), 0), 2) AS ARPAC_usd,
    
    -- Speed Insight: Average TTV for the segment
    ROUND(AVG(user_ttv_hours), 1) AS avg_time_to_value_hours,
    
    -- Efficiency Insight: Blended Take Rate
    ROUND((SUM(revenue_usd) / NULLIF(SUM(tpv_usd), 0)) * 100, 3) AS take_rate_pct

FROM enriched_financials
GROUP BY 1, 2, 3, 4 
ORDER BY month ASC, country, is_new_user DESC;
