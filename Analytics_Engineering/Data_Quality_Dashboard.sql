-- 1. STRUCTURAL: Duplicate Check (Users)
-- Checks for duplicate primary keys in the users table
SELECT 
    '1. Structural' as Layer,
    'Duplicate Check (Users)' as Check_Name,
    CASE WHEN (count(*) - count(DISTINCT user_id)) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END as Status,
    CASE WHEN (count(*) - count(DISTINCT user_id)) = 0 THEN 'Data is clean' ELSE concat('Critical: ', count(*) - count(DISTINCT user_id), ' duplicate records found') END as Message
FROM users_raw

UNION ALL

-- 1. STRUCTURAL: Duplicate Check (Events)
-- Checks for technical duplicates (Same User + Same Event + Same Timestamp)
SELECT 
    '1. Structural',
    'Duplicate Check (Events)',
    CASE WHEN (count(*) - count(DISTINCT user_id, event_name, event_timestamp)) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN (count(*) - count(DISTINCT user_id, event_name, event_timestamp)) = 0 THEN 'Data is clean' ELSE 'Warning: Technical duplicates detected in event logs' END
FROM events_raw

UNION ALL

-- 1. STRUCTURAL: Duplicate Check (Transactions)
-- Checks for duplicate transaction IDs
SELECT 
    '1. Structural',
    'Duplicate Check (Trans)',
    CASE WHEN (count(*) - count(DISTINCT transaction_id)) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN (count(*) - count(DISTINCT transaction_id)) = 0 THEN 'Data is clean' ELSE 'Critical: Duplicate transaction IDs detected' END
FROM transactions_raw

UNION ALL

-- 1. STRUCTURAL: Null Safety Check
-- Ensures critical financial data is not missing
SELECT 
    '1. Structural',
    'Null Safety Check',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0 THEN 'No nulls detected' ELSE concat('Failed: ', count(*), ' rows have null keys/amounts') END
FROM transactions_raw 
WHERE user_id IS NULL OR amount IS NULL OR transaction_id IS NULL

UNION ALL

-- 2. INTEGRITY: Referential Integrity
-- Ensures every transaction belongs to a known user
SELECT 
    '2. Integrity',
    'Referential Integrity',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0 THEN 'All transactions linked to users' ELSE concat('Failed: ', count(*), ' orphan transactions detected') END
FROM transactions_raw t 
LEFT ANTI JOIN users_raw u ON t.user_id = u.user_id

UNION ALL

-- 2. INTEGRITY: Funnel Completeness
-- Ensures users didn't spend money without ever submitting KYC
SELECT 
    '2. Integrity',
    'Funnel Completeness',
    CASE WHEN count(DISTINCT t.user_id) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(DISTINCT t.user_id) = 0 THEN 'Funnel logic holds' ELSE 'Failed: Users skipped KYC steps' END
FROM transactions_raw t 
LEFT ANTI JOIN events_raw e ON t.user_id = e.user_id AND e.event_name = 'kyc_submitted'

UNION ALL

-- 2. INTEGRITY: Activation State Machine
-- Verifies the Chronological Chain: KYC -> Activation -> Transaction
SELECT 
    '2. Integrity',
    'Activation State Machine',
    CASE WHEN count(DISTINCT t.user_id) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(DISTINCT t.user_id) = 0 THEN 'Activation sequence is valid' ELSE 'Critical: Logical failure in activation flow' END
FROM transactions_raw t
JOIN events_raw kyc ON t.user_id = kyc.user_id AND kyc.event_name = 'kyc_submitted'
LEFT JOIN events_raw act ON t.user_id = act.user_id AND act.event_name = 'account_activated'
WHERE act.event_timestamp IS NULL 
   OR act.event_timestamp < kyc.event_timestamp 
   OR act.event_timestamp > t.timestamp

UNION ALL

-- 2. INTEGRITY: Chronological Consistency
-- Checks if account creation happened before transactions (Time Travel Check)
SELECT 
    '2. Integrity',
    'Chronological Consistency',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0 THEN 'Timeline is valid' ELSE 'Failed: User spent money before account creation' END
FROM transactions_raw t 
JOIN users_raw u ON t.user_id = u.user_id 
WHERE t.timestamp <= u.created_at

UNION ALL

-- 3. RISK & ANOMALY: Bot Velocity Check (<30s)
-- Identifies users who completed the KYC flow impossibly fast
SELECT 
    '3. Risk & Anomaly',
    'Bot Velocity Check (<30s)',
    CASE WHEN count(DISTINCT user_id) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(DISTINCT user_id) = 0 THEN 'No bot behavior detected' ELSE 'Warning: High-velocity KYC submissions detected' END
FROM events_raw 
WHERE event_name IN ('landed_on_kyc', 'kyc_submitted') 
GROUP BY user_id 
HAVING (unix_timestamp(max(case when event_name='kyc_submitted' then event_timestamp end)) - 
        unix_timestamp(max(case when event_name='landed_on_kyc' then event_timestamp end))) < 30;
