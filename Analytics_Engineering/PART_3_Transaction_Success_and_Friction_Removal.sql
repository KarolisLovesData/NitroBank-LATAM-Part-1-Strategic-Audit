/**
 * MARKET AUTHORIZATION RATES
 * PURPOSE: Maps transaction success across geographies and acquisition channels 
 * to pinpoint regional friction and evaluate incoming traffic quality.
 */ 
SELECT 
    country, 
    marketing_source,
    COUNT(*) AS txn_total,
    COUNT_IF(status = 'APPROVED') AS txn_approved,
    ROUND(100.0 * COUNT_IF(status = 'APPROVED') / COUNT(*), 2) AS txn_approved_pct,
    COUNT_IF(status = 'DECLINED') AS txn_declined,
    ROUND(100.0 * COUNT_IF(status = 'DECLINED') / COUNT(*), 2) AS txn_declined_pct,
    COUNT_IF(status NOT IN ('APPROVED', 'DECLINED')) AS txn_unknown
FROM silver_transactions 
LEFT JOIN silver_users USING(user_id)
GROUP BY country, marketing_source
ORDER BY txn_approved DESC;

/**
 * REVENUE LEAKAGE & RISK ANALYSIS
 * PURPOSE: Categorizes payment failures into recoverable (Soft) vs. terminal (Hard) 
 * declines to inform automated retry logic and direct fraud ops strategies.
 */
SELECT
    COUNT(*) AS declined_txns,
    COUNT_IF(decline_type = 'SOFT') AS soft_declines,
    COUNT_IF(decline_type = 'HARD') AS hard_declines,
    COUNT_IF(decline_reason = 'INSUFFICIENT_FUNDS') AS insufficient_funds_soft,
    COUNT_IF(decline_reason = 'SUSPECTED_FRAUD') AS suspected_fraud_hard,
    COUNT_IF(decline_reason = 'PIN_RETRY_EXCEEDED') AS pin_retry_exceeded_soft,
    COUNT_IF(decline_reason = 'STOLEN_CARD') AS stolen_card_hard,
    COUNT_IF(decline_reason IS NULL) AS unknown_declines
FROM silver_transactions
WHERE status ILIKE 'DECLINED';
