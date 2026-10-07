/**
 * MONTHLY "NORTH STAR" FINANCIALS FACT TABLE
 * PURPOSE: Aggregates revenue, unit economics, and user velocity into a BI-ready view.
 *
 * PORTFOLIO NOTES:
 * - FX RATES: Hardcoded to Feb 2026 estimates for demonstration. Production would use a daily 'silver_fx_rates' dimension.
 * - TIMEZONES: Stored in UTC. Production localization (e.g., America/Bogota) would be applied for precise daily/monthly cutoffs.
 * - GRAIN: One row per month x country x marketing_source x is_new_user.
 * - UNMAPPED COUNTRIES: A country missing from the FX/fee lookup returns NULL (visible), never a silent $0.
 * - EXCLUDED VOLUME: The INNER JOIN to silver_users drops approved transactions whose user_id has no signup row
 *   (no country = no USD conversion). Reconcile with the check at the bottom of this file.
 * - ORDERING: Row order is not stored in a table, so sorting is left to the querying layer (BI tool / SELECT).
 */

CREATE OR REPLACE TABLE gold_fact_financials_monthly AS

WITH fx_and_fees AS (
    -- Single source of truth for FX conversion and interchange yield per country
    -- (replaces two duplicated CASE blocks; add a country here, not in the logic)
    SELECT * FROM VALUES
        ('Colombia', 0.00025, 0.0050),
        ('Mexico',   0.055,   0.0115),
        ('Brazil',   0.18,    0.0070)
    AS t(country, usd_rate, take_rate)
),

filtered_events AS (
    -- Extract crucial funnel timestamps for velocity tracking (one row per user)
    SELECT
        user_id,
        MIN(CASE WHEN event_name = 'app_open' THEN event_timestamp END)          AS first_app_open_ts,
        MIN(CASE WHEN event_name = 'account_activated' THEN event_timestamp END) AS activation_ts
    FROM silver_events
    WHERE event_name IN ('app_open', 'account_activated')   -- filter early: only the events we need
    GROUP BY 1
),

user_journey_milestones AS (
    -- Consolidate core user dimensions and acquisition timelines (one row per user)
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
    -- Isolate global first-spend to anchor the true Time-To-Value (TTV) (one row per user)
    SELECT
        user_id,
        MIN(ts_created_at) AS global_first_spend_ts
    FROM silver_transactions
    WHERE status = 'APPROVED'
      AND user_id IS NOT NULL      -- null IDs cannot be attributed to a user
    GROUP BY 1
),

monthly_activity AS (
    -- Aggregate gross transaction behavior per user, per month
    SELECT
        DATE_TRUNC('MONTH', ts_created_at) AS month,
        user_id,
        SUM(amount) AS local_tpv,
        COUNT(*)    AS approved_count
    FROM silver_transactions
    WHERE status = 'APPROVED'
      AND user_id IS NOT NULL
    GROUP BY 1, 2
),

enriched_financials AS (
    -- Merge financials with cohort dimensions, apply FX logic, and estimate revenue.
    -- Every joined CTE is one row per user, so the grain stays one row per user-month (no fan-out).
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

        -- Velocity: Hours from initial app open to first approved transaction.
        -- Populated only in the user's first-spend month, so each user contributes ONE value
        -- (TTV is per user; repeating it on every active month would overweight frequent buyers in AVG).
        CASE
            WHEN m.month = DATE_TRUNC('MONTH', ft.global_first_spend_ts)
            THEN TIMESTAMPDIFF(SECOND, u.first_app_open_ts, ft.global_first_spend_ts) / 3600.0
        END AS user_ttv_hours,

        -- FX Normalization: Standardizing local volume to USD
        m.local_tpv * fx.usd_rate AS tpv_usd,

        -- Yield Estimation: Applying regional interchange fee models
        m.local_tpv * fx.usd_rate * fx.take_rate AS revenue_usd

    FROM monthly_activity m
    INNER JOIN user_journey_milestones u ON m.user_id = u.user_id   -- drops buyers with no signup row
    LEFT JOIN user_first_transaction ft  ON m.user_id = ft.user_id
    LEFT JOIN fx_and_fees fx             ON u.country = fx.country  -- unmapped country -> NULL, not $0
)

-- Final Aggregation: Roll up into executive "North Star" metrics
SELECT
    month,
    country,
    marketing_source,
    is_new_user,

    -- Financial Core
    ROUND(SUM(tpv_usd), 2)     AS total_payment_volume_usd,
    ROUND(SUM(revenue_usd), 2) AS gross_revenue_usd,
    COUNT(DISTINCT user_id)    AS active_paying_users,

    -- Unit Economics (ARPU)
    ROUND(SUM(revenue_usd) / NULLIF(COUNT(DISTINCT user_id), 0), 2) AS ARPAC_usd,

    -- Speed Insight: Average TTV for the segment (one value per user)
    ROUND(AVG(user_ttv_hours), 1) AS avg_time_to_value_hours,

    -- Efficiency Insight: Blended Take Rate
    ROUND(100.0 * SUM(revenue_usd) / NULLIF(SUM(tpv_usd), 0), 3) AS take_rate_pct

FROM enriched_financials
GROUP BY 1, 2, 3, 4;


/**
 * VALIDATION CHECKS (run after the build)
 *
 * 1) Unmapped countries (expected: no rows)
 *    SELECT country, SUM(active_paying_users) AS users
 *    FROM gold_fact_financials_monthly
 *    WHERE total_payment_volume_usd IS NULL
 *    GROUP BY country;
 *
 * 2) Approved buyers excluded by the INNER JOIN (no signup row)
 *    SELECT COUNT(DISTINCT user_id)
 *    FROM silver_transactions t
 *    WHERE status = 'APPROVED' AND user_id IS NOT NULL
 *      AND NOT EXISTS (SELECT 1 FROM silver_users u WHERE u.user_id = t.user_id);
 */
