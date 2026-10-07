/**
 * DATA QUALITY DASHBOARD (BRONZE LAYER GUARDRAILS)
 *
 * PURPOSE:
 * Diagnostic SQL checks that run on the raw (Bronze) tables BEFORE data reaches the Silver layer.
 * Every check returns exactly one row: Layer | Check_Name | Status | Message.
 *
 * PORTFOLIO NOTES:
 * - ONE ROW PER CHECK: Each check is an aggregate without GROUP BY, so it always returns a row
 *   (PASS when nothing is flagged). A check built on GROUP BY would return zero rows when
 *   nothing is flagged, and the check would silently disappear from the dashboard.
 * - COUNTED MESSAGES: Failure messages state how many rows/users failed, so the result is actionable.
 * - STATUS SCOPE: "Funnel Completeness", "Activation State Machine" and "Chronological Consistency"
 *   look at ALL transaction attempts (approved and declined). If the business rule is
 *   "approved spend only", add AND t.status = 'APPROVED' to those three checks.
 * - NULL BEHAVIOR: COUNT(DISTINCT col) skips NULLs, so a NULL in a key column shows up as a
 *   "duplicate" in the structural checks. The messages say so.
 * - EXPECTED RESULT: On healthy data every check is PASS. A FAIL is a finding to investigate,
 *   not an error in the check.
 */

-- Shared per-user milestones for the Activation State Machine check (one row per user).
-- MIN() makes the check robust to retries: only the FIRST KYC and FIRST activation matter.
WITH event_milestones AS (
    SELECT
        user_id,
        MIN(CASE WHEN event_name = 'kyc_submitted'     THEN event_timestamp END) AS first_kyc_ts,
        MIN(CASE WHEN event_name = 'account_activated' THEN event_timestamp END) AS first_activation_ts
    FROM events_raw
    WHERE event_name IN ('kyc_submitted', 'account_activated')   -- filter early
    GROUP BY user_id
),

first_transactions AS (
    SELECT
        user_id,
        MIN(timestamp) AS first_txn_ts
    FROM transactions_raw
    WHERE user_id IS NOT NULL
    GROUP BY user_id
)

-- 1. STRUCTURAL: Duplicate Check (Users)
-- Checks for duplicate primary keys in the users table
SELECT
    '1. Structural' AS Layer,
    'Duplicate Check (Users)' AS Check_Name,
    CASE WHEN (count(*) - count(DISTINCT user_id)) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END AS Status,
    CASE WHEN (count(*) - count(DISTINCT user_id)) = 0
         THEN 'Data is clean'
         ELSE concat('Critical: ', count(*) - count(DISTINCT user_id), ' duplicate or null user_id records found')
    END AS Message
FROM users_raw

UNION ALL

-- 1. STRUCTURAL: Duplicate Check (Events)
-- Checks for technical duplicates (Same User + Same Event + Same Timestamp)
SELECT
    '1. Structural',
    'Duplicate Check (Events)',
    CASE WHEN (count(*) - count(DISTINCT user_id, event_name, event_timestamp)) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN (count(*) - count(DISTINCT user_id, event_name, event_timestamp)) = 0
         THEN 'Data is clean'
         ELSE concat('Warning: ', count(*) - count(DISTINCT user_id, event_name, event_timestamp),
                     ' technical duplicates or rows with a null key column in event logs')
    END
FROM events_raw

UNION ALL

-- 1. STRUCTURAL: Duplicate Check (Transactions)
-- Checks for duplicate transaction IDs
SELECT
    '1. Structural',
    'Duplicate Check (Trans)',
    CASE WHEN (count(*) - count(DISTINCT transaction_id)) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN (count(*) - count(DISTINCT transaction_id)) = 0
         THEN 'Data is clean'
         ELSE concat('Critical: ', count(*) - count(DISTINCT transaction_id), ' duplicate or null transaction IDs detected')
    END
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
-- Ensures every transaction belongs to a known user (any row in users_raw)
SELECT
    '2. Integrity',
    'Referential Integrity',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0 THEN 'All transactions linked to users' ELSE concat('Failed: ', count(*), ' orphan transactions detected') END
FROM transactions_raw t
LEFT ANTI JOIN users_raw u ON t.user_id = u.user_id

UNION ALL

-- 2. INTEGRITY: Referential Integrity (Registered Users)
-- Ensures every transaction belongs to a REGISTERED user, the same population silver_users keeps.
-- A transaction that fails here disappears from any INNER JOIN to silver_users downstream.
SELECT
    '2. Integrity',
    'Referential Integrity (Registered)',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0
         THEN 'All transactions linked to registered users'
         ELSE concat('Failed: ', count(*), ' transactions belong to users missing from the registered set')
    END
FROM transactions_raw t
LEFT ANTI JOIN (SELECT user_id FROM users_raw WHERE is_registered = true) u
    ON t.user_id = u.user_id

UNION ALL

-- 2. INTEGRITY: Funnel Completeness
-- Ensures users didn't spend money without ever submitting KYC
SELECT
    '2. Integrity',
    'Funnel Completeness',
    CASE WHEN count(DISTINCT t.user_id) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(DISTINCT t.user_id) = 0
         THEN 'Funnel logic holds'
         ELSE concat('Failed: ', count(DISTINCT t.user_id), ' users transacted without submitting KYC')
    END
FROM transactions_raw t
LEFT ANTI JOIN events_raw e ON t.user_id = e.user_id AND e.event_name = 'kyc_submitted'

UNION ALL

-- 2. INTEGRITY: Activation State Machine
-- Verifies the Chronological Chain: KYC -> Activation -> Transaction.
-- Works on one row per user (first KYC, first activation, first transaction), so retries and
-- repeat transactions cannot multiply rows or trigger false failures.
SELECT
    '2. Integrity',
    'Activation State Machine',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0
         THEN 'Activation sequence is valid'
         ELSE concat('Critical: ', count(*), ' users break the KYC -> Activation -> Transaction order')
    END
FROM first_transactions f
INNER JOIN event_milestones m ON f.user_id = m.user_id
WHERE m.first_kyc_ts IS NOT NULL                       -- users with no KYC are covered by Funnel Completeness
  AND (   m.first_activation_ts IS NULL                -- transacted after KYC but never activated
       OR m.first_activation_ts < m.first_kyc_ts       -- activated before KYC
       OR m.first_activation_ts > f.first_txn_ts)      -- transacted before activation

UNION ALL

-- 2. INTEGRITY: Chronological Consistency
-- Checks if account creation happened before transactions (Time Travel Check)
SELECT
    '2. Integrity',
    'Chronological Consistency',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0
         THEN 'Timeline is valid'
         ELSE concat('Failed: ', count(*), ' transactions occurred at or before account creation')
    END
FROM transactions_raw t
INNER JOIN users_raw u ON t.user_id = u.user_id
WHERE t.timestamp <= u.created_at

UNION ALL

-- 3. RISK & ANOMALY: Bot Velocity Check (<30s)
-- Identifies users who completed the KYC flow impossibly fast.
-- The per-user filter sits in a subquery and the outer COUNT(*) makes the check return one row:
-- a GROUP BY user_id at the top level would return one row per flagged user, and no row at all
-- (instead of PASS) when no user is flagged.
-- Gap = first landing to first submission. A negative gap (submitted before landing) is an
-- event-ordering problem, not bot speed, so it is excluded here.
SELECT
    '3. Risk & Anomaly',
    'Bot Velocity Check (<30s)',
    CASE WHEN count(*) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END,
    CASE WHEN count(*) = 0
         THEN 'No bot behavior detected'
         ELSE concat('Warning: ', count(*), ' users submitted KYC within 30 seconds of landing')
    END
FROM (
    SELECT user_id
    FROM events_raw
    WHERE event_name IN ('landed_on_kyc', 'kyc_submitted')
    GROUP BY user_id
    HAVING TIMESTAMPDIFF(
               SECOND,
               MIN(CASE WHEN event_name = 'landed_on_kyc'  THEN event_timestamp END),
               MIN(CASE WHEN event_name = 'kyc_submitted' THEN event_timestamp END)
           ) >= 0
       AND TIMESTAMPDIFF(
               SECOND,
               MIN(CASE WHEN event_name = 'landed_on_kyc'  THEN event_timestamp END),
               MIN(CASE WHEN event_name = 'kyc_submitted' THEN event_timestamp END)
           ) < 30
) fast_kyc;
