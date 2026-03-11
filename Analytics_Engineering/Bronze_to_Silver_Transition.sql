
-- 1. SILVER USERS
-- Logic: Dedupe, Rename, and Cluster by Region/Time
-- Optimization: CLUSTER BY allows fast filtering by country and time
-- 1. SILVER USERS
-- Logic: Filter for registered users only, dedupe, and cluster for performance.
-- Strategy: We treat this as a "Pure Dimension" table. Ghost users live in silver_events.

CREATE OR REPLACE TABLE silver_users 
CLUSTER BY (country, user_created_at) 
AS
SELECT 
    user_id,
    created_at AS user_created_at, 
    marketing_source,
    country,
    'REGISTERED' as account_status 
FROM users_raw
WHERE is_registered = true 
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_id 
    ORDER BY created_at DESC
) = 1;

-- 2. SILVER TRANSACTIONS
-- Logic: Dedupe, Rename Timestamp, and Cluster for Time-Range Queries
-- Optimization: CLUSTER BY time is critical for financial reporting

CREATE OR REPLACE TABLE silver_transactions
CLUSTER BY (ts_created_at, user_id) -- <--- LIQUID CLUSTERING
AS
SELECT 
    transaction_id,
    user_id,
    amount,
    timestamp as ts_created_at,
    status,
    decline_type,
    decline_reason
FROM transactions_raw
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY transaction_id --filter for unique transactions
    ORDER BY timestamp DESC
) = 1;



-- 3. SILVER EVENTS 
-- Logic: Generate Surrogate Key (MD5), Dedupe by Content, Cluster by Event Type
-- Optimization: clustering by event type makes queries much faster and efficient


CREATE OR REPLACE TABLE silver_events
CLUSTER BY (country, event_name, event_timestamp) -- <--- OPTIMIZED LIQUID CLUSTERING
AS
SELECT 
    -- SURROGATE KEY GENERATION
    -- Deterministic hash based on the identity of the action
    md5(concat(user_id, event_name, cast(event_timestamp as string))) as event_id,
    
    user_id,
    event_timestamp,
    event_name,
    country,           
    marketing_source,  
    device_brand,
    device_model,
    os_name,
    os_version
FROM events_raw
QUALIFY ROW_NUMBER() OVER (
    -- DEDUPLICATION
    -- Kept the partition on user/event/time to ensure there is no duplicate signals
    PARTITION BY user_id, event_name, event_timestamp 
    ORDER BY event_timestamp DESC
) = 1;

--Data validation in the silver layer 

SELECT 
    'Users' as Table_Name, 
    (SELECT count(*) FROM users_raw) as Bronze_Count, 
    (SELECT count(*) FROM silver_users) as Silver_Count
UNION ALL
SELECT 
    'Transactions', 
    (SELECT count(*) FROM transactions_raw), 
    (SELECT count(*) FROM silver_transactions)
UNION ALL
SELECT 
    'Events', 
    (SELECT count(*) FROM events_raw), 
    (SELECT count(*) FROM silver_events);
