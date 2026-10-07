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
 *
 * PORTFOLIO NOTES:
 * - GRAIN: One row per cohort_date x country x marketing_source x os_name.
 *   Upstream, every CTE is one row per user, so no step multiplies rows.
 * - DETERMINISTIC COHORT: Country, OS and marketing source come from the user's FIRST app_open event
 *   (ordered by timestamp, then event_id). FIRST() without an ordering returns an arbitrary row.
 * - NULL-SAFE VELOCITY: Spark's GREATEST() skips NULLs, so GREATEST(0, NULL) returns 0.
 *   Each duration is therefore computed only when BOTH timestamps exist; otherwise it stays NULL
 *   and AVG ignores it. Negative durations are still clamped to 0 (see validation checks).
 * - AVERAGES ARE NOT RE-AGGREGATABLE: The avg_hours_* columns are daily averages. Rolling them up
 *   across days with AVG() gives an average of averages. Use the funnel volumes for roll-ups.
 * - TIMEZONES: Timestamps are UTC. Production localization (e.g., America/Bogota) would be applied
 *   for precise daily cutoffs.
 * - FUNNEL DENOMINATORS: Each step rate divides by the previous step's count. This reads as
 *   "% of previous step" only if each step's users are a subset of the previous step's users
 *   (see validation check 2).
 */

-- 1. GOLD LAYER ETL: Daily Funnel Performance Fact Table
CREATE OR REPLACE TABLE gold_fact_funnel_daily AS

WITH cohort_base AS (
    -- Establish the base cohort size by capturing the exact moment of initial app entry.
    -- Locks in user dimensions from the FIRST app_open event (one row per user).
    SELECT
        user_id,
        event_timestamp AS first_open_ts,
        os_name,
        country,
        marketing_source
    FROM silver_events
    WHERE event_name = 'app_open'                       -- filter early: only acquisition events
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY user_id
        ORDER BY event_timestamp, event_id              -- event_id breaks timestamp ties deterministically
    ) = 1
),

user_signups AS (
    -- Determine top-of-funnel conversion by identifying successful backend registrations,
    -- preserving the original cohort size for accurate downstream percentage calculations.
    -- LEFT JOIN keeps unregistered users ("ghost users"); silver_users is unique per user_id.
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
    -- The event filter sits inside the subquery, so only the two milestone events are joined.
    SELECT
        s.user_id,
        s.first_open_ts,
        s.os_name,
        s.country,
        s.marketing_source,
        s.account_created_ts,
        s.has_created_account,
        MAX(CASE WHEN e.event_name = 'kyc_submitted' THEN 1 ELSE 0 END)              AS has_submitted_kyc,
        MAX(CASE WHEN e.event_name = 'account_activated' THEN 1 ELSE 0 END)          AS has_activated,
        MIN(CASE WHEN e.event_name = 'account_activated' THEN e.event_timestamp END) AS activation_ts
    FROM user_signups s
    LEFT JOIN (
        SELECT user_id, event_name, event_timestamp
        FROM silver_events
        WHERE event_name IN ('kyc_submitted', 'account_activated')
    ) e
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
    LEFT JOIN (
        SELECT user_id, ts_created_at
        FROM silver_transactions
        WHERE status = 'APPROVED'                       -- filter early: approved spend only
          AND user_id IS NOT NULL
    ) t
        ON f.user_id = t.user_id
        AND t.ts_created_at >= f.first_open_ts
    GROUP BY ALL
),

user_velocity AS (
    -- Per-user stage durations in hours (one row per user).
    -- A duration exists only when BOTH of its timestamps exist; otherwise it is NULL,
    -- so users who never reached a stage are excluded from that stage's average.
    -- GREATEST(0, ...) safeguards against negative durations from data latency or out-of-order logs.
    SELECT
        *,
        CASE WHEN account_created_ts IS NOT NULL
             THEN GREATEST(0, TIMESTAMPDIFF(SECOND, first_open_ts, account_created_ts)) / 3600.0
        END AS hours_open_to_create,
        CASE WHEN account_created_ts IS NOT NULL AND activation_ts IS NOT NULL
             THEN GREATEST(0, TIMESTAMPDIFF(SECOND, account_created_ts, activation_ts)) / 3600.0
        END AS hours_create_to_active,
        CASE WHEN activation_ts IS NOT NULL AND first_trans_ts IS NOT NULL
             THEN GREATEST(0, TIMESTAMPDIFF(SECOND, activation_ts, first_trans_ts)) / 3600.0
        END AS hours_active_to_value
    FROM final_metrics
)

-- Final Aggregation: Roll up individual event timelines into daily performance metrics.
SELECT
    DATE_TRUNC('DAY', first_open_ts) AS cohort_date,
    country,
    marketing_source,
    COALESCE(os_name, 'Unknown') AS os_name,

    -- Funnel Volumes
    COUNT(user_id)             AS total_app_opens,
    SUM(has_created_account)   AS users_created_account,
    SUM(has_submitted_kyc)     AS users_submitted_kyc,
    SUM(has_activated)         AS users_activated,
    COUNT(first_trans_ts)      AS users_transacted,

    -- Velocity Metrics (Time-to-Value): average hours between stages, among users who reached both ends
    ROUND(AVG(hours_open_to_create), 2)   AS avg_hours_open_to_create,
    ROUND(AVG(hours_create_to_active), 2) AS avg_hours_create_to_active,
    ROUND(AVG(hours_active_to_value), 2)  AS avg_hours_active_to_value

FROM user_velocity
GROUP BY ALL;

/*
 * -----------------------------------------------------------------------------
 * 2. BUSINESS REPORTING: Marketing Cohort Funnel Conversion
 * Provides the final conversion percentages for leadership dashboards.
 * Rates stay numeric (no '%' text) so BI tools can sort, filter and chart them.
 * -----------------------------------------------------------------------------
 */

SELECT
    country,
    marketing_source,
    SUM(total_app_opens) AS cohort_size,

    -- Acquisition Efficiency
    ROUND(100.0 * SUM(users_created_account) / NULLIF(SUM(total_app_opens), 0), 2)      AS step1_signup_rate_pct,

    -- Onboarding & Compliance Friction
    ROUND(100.0 * SUM(users_submitted_kyc) / NULLIF(SUM(users_created_account), 0), 2)  AS step2_doc_submission_rate_pct,
    ROUND(100.0 * SUM(users_activated) / NULLIF(SUM(users_submitted_kyc), 0), 2)        AS step3_approval_rate_pct,

    -- Activation & Funding Efficiency
    ROUND(100.0 * SUM(users_transacted) / NULLIF(SUM(users_activated), 0), 2)           AS step4_funding_rate_pct,

    -- Ultimate Campaign ROI: From initial tap to realized revenue
    ROUND(100.0 * SUM(users_transacted) / NULLIF(SUM(total_app_opens), 0), 2)           AS global_monetization_rate_pct

FROM gold_fact_funnel_daily
GROUP BY country, marketing_source
ORDER BY cohort_size DESC;

/*
 * -----------------------------------------------------------------------------
 * VALIDATION CHECKS (run after the build)
 * -----------------------------------------------------------------------------
 *
 * 1) One row per user in the cohort (expected: total_rows = distinct_users)
 *    SELECT COUNT(*) AS total_rows, COUNT(DISTINCT user_id) AS distinct_users
 *    FROM (SELECT user_id FROM silver_events WHERE event_name = 'app_open' GROUP BY user_id);
 *    -- and SUM(total_app_opens) in gold_fact_funnel_daily should equal distinct_users
 *
 * 2) Are funnel steps subsets of the previous step? (expected: all three counts = 0)
 *    -- If not, the step rates are not "% of previous step".
 *    SELECT
 *      SUM(CASE WHEN has_submitted_kyc = 1 AND has_created_account = 0 THEN 1 ELSE 0 END) AS kyc_without_account,
 *      SUM(CASE WHEN has_activated = 1 AND has_submitted_kyc = 0 THEN 1 ELSE 0 END)       AS activated_without_kyc,
 *      SUM(CASE WHEN first_trans_ts IS NOT NULL AND has_activated = 0 THEN 1 ELSE 0 END)  AS transacted_without_activation
 *    FROM final_metrics;   -- run inside the CREATE TABLE CTE chain, or as a temp view
 *
 * 3) Negative durations clamped to 0 (informational: how many users the safeguard touched)
 *    SELECT
 *      SUM(CASE WHEN account_created_ts < first_open_ts THEN 1 ELSE 0 END) AS create_before_open,
 *      SUM(CASE WHEN activation_ts < account_created_ts THEN 1 ELSE 0 END) AS active_before_create,
 *      SUM(CASE WHEN first_trans_ts < activation_ts THEN 1 ELSE 0 END)     AS trans_before_active
 *    FROM final_metrics;
 */
