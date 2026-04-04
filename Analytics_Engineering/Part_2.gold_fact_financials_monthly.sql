/* Monthly "North Star" Metrics: Slicing Revenue, Risk, and Speed.
   
   PORTFOLIO NOTE - FX RATES:
   For the scope of this project, FX rates are hardcoded to Feb 2026 estimates to demonstrate logic.
   In a production environment, I would use a scalable approach like
   orchestrating a daily pipeline to extract live rates from a currency API into a 'silver_fx_rates' 
   dimension table, and performing a time-series JOIN on the transaction date.
   PORTFOLIO NOTE - TIMEZONE HANDLING:
   All timestamps in this dataset are ingested, stored, and aggregated in UTC. 
   In a live production environment for LATAM, I would apply localized timezone conversions (e.g., DATE(ts_created_at, 'America/Bogota')) 
   to ensure daily/monthly revenue cutoffs align perfectly with local business operations.

   Business Logic:
   1. TTV: Time from 'App Open' to 'First Transaction' (The full user journey).
   2. FX Normalization: Standardized to USD (see portfolio note above).
   3. Dimensions: Marketing Source and Country for acquisition performance analysis.
*/ 

CREATE OR REPLACE TABLE gold_fact_financials_monthly AS 
WITH filtered_events AS (
    SELECT 
        user_id,
        MIN(CASE WHEN event_name = 'app_open' THEN event_timestamp END) AS first_app_open_ts,
        MIN(CASE WHEN event_name = 'account_activated' THEN event_timestamp END) AS activation_ts
    FROM silver_events
    WHERE event_name IN ('app_open', 'account_activated') --Filtered only the data needed
    GROUP BY 1
),
user_journey_milestones AS (
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
    INNER JOIN user_journey_milestones u ON m.user_id = u.user_id  --only transactions with verified users in Gold Table 
    LEFT JOIN user_first_transaction ft ON m.user_id = ft.user_id  --attaches the very first user transaction 
)

-- 5. Final Gold Table Output 
SELECT 
    month,
    country,
    marketing_source, 
    is_new_user, -- Added as a dimension
    
    -- Financial Core
    ROUND(SUM(tpv_usd), 2) AS total_payment_volume_usd,
    ROUND(SUM(revenue_usd), 2) AS gross_revenue_usd,
    COUNT(DISTINCT user_id) AS active_paying_users,
    
    -- Unit Economics (Now automatically calculates per segment)
    ROUND(SUM(revenue_usd) / NULLIF(COUNT(DISTINCT user_id), 0), 2) AS ARPAC_usd,
    
    -- Speed Insight: Average TTV (Will naturally be 0 for existing users)
    ROUND(AVG(user_ttv_hours), 1) AS avg_time_to_value_hours,
    
    -- Efficiency Insight: Take Rate
    ROUND((SUM(revenue_usd) / NULLIF(SUM(tpv_usd), 0)) * 100, 3) AS take_rate_pct

FROM enriched_financials
GROUP BY 1, 2, 3, 4 -- Added is_new_user to the grouping
ORDER BY month ASC, country, is_new_user DESC;
