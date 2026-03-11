--Customer funnel analysis the final quuery for the business for the analysis

SELECT country,
       marketing_source,
    SUM(total_app_opens) AS cohort_size,
    
    -- Step 1: App Open --> Account Created 
    ROUND(SUM(users_created_account) / NULLIF(SUM(total_app_opens), 0) * 100, 2) || '%' AS step1_signup_rate,  
    
    -- Step 2: Account Created --> KYC Submitted
    ROUND(SUM(users_submitted_kyc) / NULLIF(SUM(users_created_account), 0) * 100, 2) || '%' AS step2_doc_submission_rate,
    
    -- Step 3: KYC Submitted --> Account Activated
    ROUND(SUM(users_activated) / NULLIF(SUM(users_submitted_kyc), 0) * 100, 2) || '%' AS step3_approval_rate,
    
    -- Step 4: Account Activated --> First Transaction
    ROUND(SUM(users_transacted) / NULLIF(SUM(users_activated), 0) * 100, 2) || '%' AS step4_funding_rate,

    -- Global conversion from App Open to Revenue (only user_id with APPROVED transaction)
    ROUND(SUM(users_transacted) / NULLIF(SUM(total_app_opens), 0) * 100, 2) || '%' AS global_monetization_rate

FROM gold_fact_funnel_daily
GROUP BY country, marketing_source
ORDER BY cohort_size DESC;      



-- GOLD LAYER: Daily Funnel Performance
--This is the query that was used to create BI ready Gold Layer table
-- Strategy: Cohort-based funnel tracking to monitor conversion and velocity

CREATE OR REPLACE TABLE gold_fact_funnel_daily AS 

WITH cohort_base AS (
    -- 1. ENTRY POINT: Every unique person who opened the app.
    -- Using 'FIRST' to lock in the dimensions (Country/Source) at the exact moment of entry.
    SELECT 
        user_id,
        MIN(event_timestamp) AS first_open_ts,
        FIRST(os_name) AS os_name, --FIRST was used to identify the original source that brought the user in
        FIRST(country) AS country,          
        FIRST(marketing_source) AS marketing_source 
    FROM silver_events
    WHERE event_name = 'app_open'  --this is the top of the funnel, all conversions will be percentage of # of 'app_open' events
    GROUP BY 1                        
),

user_signups AS (
    -- 2. SIGNUP CHECK: Identify users who successfully reached the backend registration table.
    SELECT 
        c.user_id,
        c.first_open_ts,
        c.os_name,
        c.country,            
        c.marketing_source,  
        u.user_created_at AS account_created_ts,
        CASE WHEN u.user_id IS NOT NULL THEN 1 ELSE 0 END AS has_created_account  --produces a binary result 
    FROM cohort_base c
    LEFT JOIN silver_users u   --LEFT JOIN used to keep all the people you opened the app to calculate conversion rates 
        ON c.user_id = u.user_id
),

funnel_events AS (
    -- 3. INTERMEDIATE STEPS: Flag KYC Submission and Account Activation events.
    SELECT 
        s.user_id,
        s.first_open_ts,
        s.os_name,
        s.country,
        s.marketing_source,
        s.account_created_ts,
        s.has_created_account,
        
        -- used MAX to essentially flatten the massive log of events a user might have
        -- MIN is used to capture the very first activation event
        MAX(CASE WHEN e.event_name = 'kyc_submitted' THEN 1 ELSE 0 END) AS has_submitted_kyc,          
        MAX(CASE WHEN e.event_name = 'account_activated' THEN 1 ELSE 0 END) AS has_activated,          
        MIN(CASE WHEN e.event_name = 'account_activated' THEN e.event_timestamp END) AS activation_ts   
    FROM user_signups s
    LEFT JOIN silver_events e 
        ON s.user_id = e.user_id 
        AND e.event_timestamp >= s.first_open_ts  --chronological guardrail, KYC,Activation happens after the app open 
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),

final_metrics AS (
    -- 4. MONETIZATION: Link users to their first APPROVED transaction.
    -- Ensures we only count monetized users originating from our specific traffic cohort.
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
        MIN(t.ts_created_at) AS first_trans_ts   --captured the very first transactions
    FROM funnel_events f
    LEFT JOIN silver_transactions t 
        ON TRIM(f.user_id) = TRIM(t.user_id)    --cleaned up the user_id column to capture all user ids
        AND UPPER(t.status) = 'APPROVED'  
        AND t.ts_created_at >= f.first_open_ts
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
)

-- 5. DAILY AGGREGATION & VELOCITY CALCULATION
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
    
    -- Time-to-Value (Velocity in Hours)/ Convert to epoch, force 0 to prevent negative durations caused by system latency or out-of-order logs., and scale to hours
    ROUND(AVG(GREATEST(0, unix_timestamp(account_created_ts) - unix_timestamp(first_open_ts)) / 3600), 2) AS avg_hours_open_to_create,
    ROUND(AVG(GREATEST(0, unix_timestamp(activation_ts) - unix_timestamp(account_created_ts)) / 3600), 2) AS avg_hours_create_to_active,
    ROUND(AVG(GREATEST(0, unix_timestamp(first_trans_ts) - unix_timestamp(activation_ts)) / 3600), 2) AS avg_hours_active_to_value

FROM final_metrics
GROUP BY 1, 2, 3, 4;
