/**
 * CUSTOMER FUNNEL & TIME-TO-VALUE (TTV) ANALYSIS PIPELINE
 * 
 * PURPOSE: 
 * Builds a cohort-based tracking model to monitor the end-to-end user journey 
 * from acquisition to first monetization.
 *
 * COMPONENTS:
 * 1. gold_fact_funnel_daily (ETL): Aggregates Silver-layer event logs into a BI-ready fact table, 
 *    calculating both conversion volume and velocity (TTV in hours) between milestones.
 * 2. Funnel Performance View: Calculates exact conversion rates across the pipeline, 
 *    segmented by country and marketing source for campaign ROI evaluation.
 */

-- 1. GOLD LAYER ETL: Daily Funnel Performance Fact Table
CREATE OR REPLACE TABLE gold_fact_funnel_daily AS 

WITH cohort_base AS (
    -- Establish the base cohort size by capturing the exact moment of initial app entry.
    -- Locks in user dimensions based on their original acquisition touchpoint.
    SELECT 
        user_id,
        MIN(event_timestamp) AS first_open_ts,
        FIRST(os_name) AS os_name, 
        FIRST(country) AS country,          
        FIRST(marketing_source) AS marketing_source 
    FROM silver_events
    WHERE event_name = 'app_open' 
    GROUP BY 1                        
),

user_signups AS (
    -- Determine top-of-funnel conversion by identifying successful backend registrations,
    -- preserving the original cohort size for accurate downstream percentage calculations.
    SELECT 
        c.user_id,
        c.first_open_ts,
        c.os_name,
        c.country,            
        c.marketing_source,  
        u.user_created_at AS account_created_ts,
        CASE WHEN u.user_id IS NOT NULL THEN 1 ELSE 0 END AS has_created_account  
    FROM cohort_base c
    LEFT JOIN silver_users u   
        ON c.user_id = u.user_id
),

funnel_events AS (
    -- Extract key operational milestones (KYC and Activation). 
    -- Enforces chronological progression to prevent attributing pre-existing 
    -- or unrelated historical events to the new acquisition cohort.
    SELECT 
        s.user_id,
        s.first_open_ts,
        s.os_name,
        s.country,
        s.marketing_source,
        s.account_created_ts,
        s.has_created_account,
        MAX(CASE WHEN e.event_name = 'kyc_submitted' THEN 1 ELSE 0 END) AS has_submitted_kyc,          
        MAX(CASE WHEN e.event_name = 'account_activated' THEN 1 ELSE 0 END) AS has_activated,          
        MIN(CASE WHEN e.event_name = 'account_activated' THEN e.event_timestamp END) AS activation_ts   
    FROM user_signups s
    LEFT JOIN silver_events e 
        ON s.user_id = e.user_id 
        AND e.event_timestamp >= s.first_open_ts 
    GROUP BY ALL
),

final_metrics AS (
    -- Identify the point of monetization (Time-To-Value) by isolating 
    -- the first successful, approved transaction that occurred post-acquisition.
    SELECT 
        f.user_id,
        f.first_open_ts,
        f.os_name,
        f.country,
        f.marketing_source,
        f.account_created_ts,
        f.has_created_account,
        f.has_submitted_kyc,
        f.has_activated,
        f.activation_ts,
        MIN(t.ts_created_at) AS first_trans_ts   
    FROM funnel_events f
    LEFT JOIN silver_transactions t 
        ON f.user_id = t.user_id
        AND t.status = 'APPROVED'  
        AND t.ts_created_at >= f.first_open_ts
    GROUP BY ALL
)

-- Final Aggregation: Roll up individual event timelines into daily performance metrics.
SELECT 
    DATE_TRUNC('DAY', first_open_ts) AS cohort_date,
    country,
    marketing_source,
    COALESCE(os_name, 'Unknown') AS os_name,
    
    -- Funnel Volumes
    COUNT(user_id) AS total_app_opens,              
    SUM(has_created_account) AS users_created_account, 
    SUM(has_submitted_kyc) AS users_submitted_kyc,     
    SUM(has_activated) AS users_activated,             
    COUNT(first_trans_ts) AS users_transacted,        
    
    -- Velocity Metrics (Time-to-Value)
    -- Calculates average hours between stages. Uses GREATEST(0) to safeguard against 
    -- negative durations caused by systemic data latency or out-of-order event logs.
    ROUND(AVG(GREATEST(0, unix_timestamp(account_created_ts) - unix_timestamp(first_open_ts)) / 3600), 2) AS avg_hours_open_to_create,
    ROUND(AVG(GREATEST(0, unix_timestamp(activation_ts) - unix_timestamp(account_created_ts)) / 3600), 2) AS avg_hours_create_to_active,
    ROUND(AVG(GREATEST(0, unix_timestamp(first_trans_ts) - unix_timestamp(activation_ts)) / 3600), 2) AS avg_hours_active_to_value

FROM final_metrics
GROUP BY ALL;

/*
 * -----------------------------------------------------------------------------
 * 2. BUSINESS REPORTING: Marketing Cohort Funnel Conversion
 * Provides the final conversion percentages for leadership dashboards.
 * -----------------------------------------------------------------------------
 */

SELECT 
    country,
    marketing_source,
    SUM(total_app_opens) AS cohort_size,
    
    -- Acquisition Efficiency
    ROUND(SUM(users_created_account) / NULLIF(SUM(total_app_opens), 0) * 100, 2) || '%' AS step1_signup_rate,  
    
    -- Onboarding & Compliance Friction
    ROUND(SUM(users_submitted_kyc) / NULLIF(SUM(users_created_account), 0) * 100, 2) || '%' AS step2_doc_submission_rate,
    ROUND(SUM(users_activated) / NULLIF(SUM(users_submitted_kyc), 0) * 100, 2) || '%' AS step3_approval_rate,
    
    -- Activation & Funding Efficiency
    ROUND(SUM(users_transacted) / NULLIF(SUM(users_activated), 0) * 100, 2) || '%' AS step4_funding_rate,

    -- Ultimate Campaign ROI: From initial tap to realized revenue
    ROUND(SUM(users_transacted) / NULLIF(SUM(total_app_opens), 0) * 100, 2) || '%' AS global_monetization_rate

FROM gold_fact_funnel_daily
GROUP BY country, marketing_source
ORDER BY cohort_size DESC;
