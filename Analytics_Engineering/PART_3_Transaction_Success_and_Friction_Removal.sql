--PART 3: TRANSACTION SUCCESS & FRICTION REMOVAL 

/*This query calculates the total number of transactions, the number of approved transactions, the percentage of approved transactions, 
  the number of declined transactions, the percentage of declined transactions, and the number of unknown transactions for each country and marketing source.*/ 
    
select country, 
    marketing_source,
    COUNT(*) as txn_total,
           COUNT(CASE WHEN status = 'APPROVED' THEN 1 END) as txn_approved,
           ROUND(100*COUNT(CASE WHEN status = 'APPROVED' THEN 1 END)/COUNT(*),2) AS txn_approved_pct,
           COUNT(CASE WHEN status = 'DECLINED' THEN 1 END) as txn_declined,
           ROUND(100*COUNT(CASE WHEN status = 'DECLINED' THEN 1 END)/COUNT(*),2) AS txn_declined_pct,
           COUNT(CASE WHEN status NOT IN ('APPROVED', 'DECLINED') THEN 1 END) as txn_unknown
    from silver_transactions 
     LEFT JOIN silver_users USING(user_ID)
     GROUP BY country, marketing_source
     ORDER BY txn_approved DESC 

--This query returns the number of declined thxns and the number of soft and hard declines for each decline type and reason
  
  SELECT
       COUNT (*) AS declined_txns,
       COUNT_IF(decline_type = 'SOFT') AS SOFT_declines,
       COUNT_IF(decline_type = 'HARD') AS HARD_declines,
       COUNT_IF(decline_reason = 'INSUFFICIENT_FUNDS') AS insufficient_funds_SOFT,
       COUNT_IF(decline_reason = 'SUSPECTED_FRAUD') AS suspected_fraud_HARD,
       COUNT_IF(decline_reason = 'PIN_RETRY_EXCEEDED') AS pin_retry_exceeded_SOFT,
       COUNT_IF(decline_reason = 'STOLEN_CARD') AS stolen_card_HARD,
       COUNT_IF(decline_reason IS NULL) AS unknown_declines
       FROM silver_transactions
       WHERE status ilike 'DECLINED'

           
