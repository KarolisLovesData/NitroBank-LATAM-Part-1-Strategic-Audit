/* Geographic & Channel Performance: 
These queries evaluate transaction health across different markets and acquisition channels. 
This view identifies where conversion is strongest and highlights potential friction 
points in the user journey. [Used COUNT_IF for radability instead of CASE WHEN]
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

/* Decline Root-Cause Analysis: 
A deep dive into failed payments to distinguish between recoverable "Soft" declines 
(like low funds) and permanent "Hard" declines (like stolen cards). 
Essential for understanding why revenue is being left on the table.
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
