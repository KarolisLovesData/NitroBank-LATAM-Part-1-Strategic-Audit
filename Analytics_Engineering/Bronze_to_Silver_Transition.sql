/**
 * BRONZE TO SILVER TRANSITION
 *
 * PURPOSE:
 * Builds the cleaned, relational Silver layer from the raw (Bronze) tables:
 * deduplicated, consistently named, and clustered for downstream query patterns.
 *
 * PORTFOLIO NOTES:
 * - DEDUPLICATION: Single-pass QUALIFY ROW_NUMBER() = 1 on each table's business key.
 *   Duplicates are dropped here; a production deployment would route them to a quarantine table
 *   (see README) so Bronze-to-Silver counts reconcile for auditors.
 * - DETERMINISTIC SURVIVORS: A dedup is only reproducible if the ORDER BY can pick between the
 *   duplicate rows. In silver_events every row in a partition shares the same event_timestamp,
 *   so the tie-break uses the remaining columns (see below).
 * - NULL KEYS: Rows with a NULL key collapse into one partition and keep a single row.
 *   The Null Safety checks in Data_Quality_Dashboard.sql (expected 0) guard this.
 * - GHOST USERS: silver_users is a pure dimension of REGISTERED users. Unregistered traffic lives
 *   in silver_events (country and marketing_source are persisted on the event row).
 * - CLUSTERING: Liquid Clustering keys follow the main filter columns of each table. On a small
 *   dimension such as silver_users the benefit is modest; the larger win is on the two fact tables.
 */

-- 1. SILVER USERS
-- Logic: Filter for REGISTERED users only, deduplicate, and cluster for performance.
-- Strategy: Treat this as a "Pure Dimension" table. Ghost users live in silver_events (essential for funnel analysis)

CREATE OR REPLACE TABLE silver_users
CLUSTER BY (country, user_created_at)
AS
SELECT
    user_id,
    created_at AS user_created_at,
    marketing_source,
    country,
    'REGISTERED' AS account_status
FROM users_raw
WHERE is_registered = true
  AND user_id IS NOT NULL            -- a NULL key cannot identify a user
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_id
    ORDER BY created_at DESC         -- keep the latest record per user
) = 1;

-- 2. SILVER TRANSACTIONS
-- Logic: Deduplicate, Rename Timestamp, and Cluster for Time-Range Queries
-- Optimization: CLUSTER BY time is critical for financial reporting

CREATE OR REPLACE TABLE silver_transactions
CLUSTER BY (ts_created_at, user_id)
AS
SELECT
    transaction_id,
    user_id,
    amount,
    timestamp AS ts_created_at,
    status,
    decline_type,
    decline_reason
FROM transactions_raw
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY transaction_id
    ORDER BY timestamp DESC          -- keep the latest record per transaction_id
) = 1;

-- 3. SILVER EVENTS
-- Logic: Generate Surrogate Key (MD5), Deduplicate by Content
-- Optimization: clustering by country, event_name, event_timestamp

CREATE OR REPLACE TABLE silver_events
CLUSTER BY (country, event_name, event_timestamp)
AS
SELECT
    -- SURROGATE KEY GENERATION
    -- Deterministic hash based on the identity of the action.
    -- concat_ws with a delimiter keeps field boundaries unambiguous ('ab'+'c' <> 'a'+'bc')
    -- and does not turn the whole key into NULL when one field is NULL (plain concat does).
    md5(concat_ws('|', user_id, event_name, CAST(event_timestamp AS STRING))) AS event_id,

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
    -- Partition on user/event/time to ensure there are no duplicate signals.
    PARTITION BY user_id, event_name, event_timestamp
    -- Every row in a partition has the same event_timestamp, so ordering by it cannot choose a
    -- survivor. Order by the remaining attributes instead (populated values first) so each rebuild
    -- keeps the same row. If Bronze has an ingestion timestamp, order by that instead.
    ORDER BY country          ASC NULLS LAST,
             marketing_source ASC NULLS LAST,
             device_brand     ASC NULLS LAST,
             device_model     ASC NULLS LAST,
             os_name          ASC NULLS LAST,
             os_version       ASC NULLS LAST
) = 1;

-- 4. DATA VALIDATION IN THE SILVER LAYER
-- Reconciles each Silver table to an independently computed expectation from Bronze.
-- Rows_Removed > 0 is normal (unregistered users, duplicates); PASS means Silver kept exactly
-- the rows the business keys say it should.

WITH recon AS (
    SELECT
        'Users' AS Table_Name,
        (SELECT count(*) FROM users_raw) AS Bronze_Count,
        (SELECT count(*) FROM (
            SELECT DISTINCT user_id FROM users_raw
            WHERE is_registered = true AND user_id IS NOT NULL
        )) AS Expected_Silver_Count,
        (SELECT count(*) FROM silver_users) AS Silver_Count

    UNION ALL

    SELECT
        'Transactions',
        (SELECT count(*) FROM transactions_raw),
        (SELECT count(*) FROM (SELECT DISTINCT transaction_id FROM transactions_raw)),
        (SELECT count(*) FROM silver_transactions)

    UNION ALL

    SELECT
        'Events',
        (SELECT count(*) FROM events_raw),
        (SELECT count(*) FROM (SELECT DISTINCT user_id, event_name, event_timestamp FROM events_raw)),
        (SELECT count(*) FROM silver_events)
)
SELECT
    Table_Name,
    Bronze_Count,
    Expected_Silver_Count,
    Silver_Count,
    Bronze_Count - Silver_Count AS Rows_Removed,
    CASE WHEN Silver_Count = Expected_Silver_Count THEN '✅ PASS' ELSE '❌ FAIL' END AS Status
FROM recon;
