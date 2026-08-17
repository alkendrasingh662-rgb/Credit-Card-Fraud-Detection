-- =====================================================================
-- FILE    : 07_ctes_advanced_analytics.sql
-- PURPOSE : CTEs (simple, chained, recursive) and advanced analytics -
--           haversine geo-distance, z-score anomaly detection, cohort
--           analysis, repeat-fraud and velocity checks.
-- =====================================================================

USE fraud_analytics;

-- =====================================================================
-- CTEs
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q38. (Simple CTE) Summarise fraud per category, then keep only the
--      categories whose fraud rate beats the overall rate - written
--      readably with a CTE instead of a nested subquery.
-- ---------------------------------------------------------------------
WITH category_stats AS (
    SELECT
        m.category,
        COUNT(*)                                   AS total_txns,
        SUM(t.is_fraud)                            AS fraud_txns,
        100 * SUM(t.is_fraud) / COUNT(*)           AS fraud_rate
    FROM Transactions t
    JOIN Merchants m ON t.merchant_id = m.merchant_id
    GROUP BY m.category
)
SELECT category, total_txns, fraud_txns, ROUND(fraud_rate,3) AS fraud_rate_pct
FROM category_stats
WHERE fraud_rate > (SELECT AVG(fraud_rate) FROM category_stats)
ORDER BY fraud_rate DESC;
-- INSIGHT: A CTE names an intermediate result so the final query reads
--          top-to-bottom. Same output as a subquery, far more maintainable.


-- ---------------------------------------------------------------------
-- Q39. (Chained CTEs) Build a customer risk score in stages: spend
--      profile -> fraud profile -> combined score.
-- ---------------------------------------------------------------------
WITH spend AS (
    SELECT cc_num, COUNT(*) AS txns, SUM(amt) AS total_spend
    FROM Transactions
    GROUP BY cc_num
),
fraud AS (
    SELECT cc_num,
           SUM(is_fraud)                       AS fraud_cnt,
           SUM(CASE WHEN is_fraud=1 THEN amt ELSE 0 END) AS fraud_amt
    FROM Transactions
    GROUP BY cc_num
),
scored AS (
    SELECT
        s.cc_num,
        s.txns,
        s.total_spend,
        f.fraud_cnt,
        f.fraud_amt,
        ROUND(100 * f.fraud_cnt / s.txns, 2)   AS pct_txns_fraud
    FROM spend s
    JOIN fraud f ON s.cc_num = f.cc_num
)
SELECT *
FROM scored
WHERE fraud_cnt > 0
ORDER BY pct_txns_fraud DESC, fraud_amt DESC
LIMIT 20;
-- INSIGHT: Multiple CTEs chain like a pipeline - each stage builds on the
--          last. Produces a ranked list of the customers most compromised
--          by fraud, with the logic broken into clear steps.


-- ---------------------------------------------------------------------
-- Q40. (Recursive CTE) Generate a continuous calendar of dates so the
--      daily fraud trend has NO missing days (zero-fill the gaps).
-- ---------------------------------------------------------------------
WITH RECURSIVE date_series AS (
    SELECT (SELECT MIN(DATE(trans_date_trans_time)) FROM Transactions) AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY
    FROM date_series
    WHERE d < (SELECT MAX(DATE(trans_date_trans_time)) FROM Transactions)
)
SELECT
    ds.d                              AS calendar_date,
    IFNULL(f.fraud_cnt, 0)           AS fraud_cnt
FROM date_series ds
LEFT JOIN (
    SELECT DATE(trans_date_trans_time) AS d, SUM(is_fraud) AS fraud_cnt
    FROM Transactions
    GROUP BY DATE(trans_date_trans_time)
) f ON ds.d = f.d
ORDER BY ds.d
LIMIT 60;
-- INSIGHT: A recursive CTE builds a row per calendar day between the first
--          and last transaction. LEFT JOINing the real counts and IFNULL-ing
--          to 0 gives a gap-free series - essential before charting a trend.
-- NOTE   : If the range is large, raise the limit first:
--          SET SESSION cte_max_recursion_depth = 10000;


-- ---------------------------------------------------------------------
-- Q41. (Recursive CTE - pure demo) Generate numbers 1..20.
-- ---------------------------------------------------------------------
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 20
)
SELECT n FROM nums;
-- INSIGHT: The minimal recursive pattern - an anchor row (1) plus a
--          recursive step (n+1) with a stop condition (n < 20). The mental
--          model behind Q40's date generator.


-- =====================================================================
-- ADVANCED ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q42. (Haversine) Does physical distance between the cardholder's home
--      and the merchant correlate with fraud?
-- ---------------------------------------------------------------------
WITH dist AS (
    SELECT
        t.is_fraud,
        6371 * ACOS(
            LEAST(1.0,                                   -- guard against float > 1
              COS(RADIANS(c.lat)) * COS(RADIANS(t.merch_lat)) *
              COS(RADIANS(t.merch_long) - RADIANS(c.`long`)) +
              SIN(RADIANS(c.lat)) * SIN(RADIANS(t.merch_lat))
            )
        ) AS distance_km
    FROM Transactions t
    JOIN Customers c ON t.cc_num = c.cc_num
)
SELECT
    CASE WHEN is_fraud=1 THEN 'Fraud' ELSE 'Legitimate' END AS txn_type,
    COUNT(*)                     AS txns,
    ROUND(AVG(distance_km), 2)   AS avg_distance_km,
    ROUND(MAX(distance_km), 2)   AS max_distance_km
FROM dist
GROUP BY is_fraud;
-- INSIGHT: The haversine formula converts two lat/long pairs into
--          great-circle km. Comparing the average distance for fraud vs
--          legit transactions tests whether "far from home" is a red flag.


-- ---------------------------------------------------------------------
-- Q43. (Z-score anomaly) Flag transactions that sit far above a
--      customer's own typical spend (statistical outliers).
-- ---------------------------------------------------------------------
WITH cust_stats AS (
    SELECT cc_num, AVG(amt) AS mean_amt, STDDEV_SAMP(amt) AS sd_amt
    FROM Transactions
    GROUP BY cc_num
)
SELECT
    t.trans_num,
    t.cc_num,
    t.amt,
    ROUND(cs.mean_amt, 2)                                    AS cust_mean,
    ROUND((t.amt - cs.mean_amt) / NULLIF(cs.sd_amt,0), 2)   AS z_score,
    t.is_fraud
FROM Transactions t
JOIN cust_stats cs ON t.cc_num = cs.cc_num
WHERE cs.sd_amt > 0
  AND (t.amt - cs.mean_amt) / cs.sd_amt > 3     -- more than 3 SD above their mean
ORDER BY z_score DESC
LIMIT 25;
-- INSIGHT: Z-score = (value - mean) / std-dev, computed PER customer. A
--          z-score above 3 means the amount is extreme relative to that
--          person's history - and these rows skew heavily toward is_fraud=1.


-- ---------------------------------------------------------------------
-- Q44. (Cohort analysis) Group customers by the MONTH of their first
--      transaction, and track how much fraud each cohort suffers.
-- ---------------------------------------------------------------------
WITH first_seen AS (
    SELECT cc_num,
           DATE_FORMAT(MIN(trans_date_trans_time), '%Y-%m') AS cohort_month
    FROM Transactions
    GROUP BY cc_num
)
SELECT
    fs.cohort_month,
    COUNT(DISTINCT fs.cc_num)                    AS cohort_size,
    SUM(t.is_fraud)                              AS fraud_txns,
    ROUND(100 * SUM(t.is_fraud)/COUNT(*), 3)     AS fraud_rate_pct
FROM first_seen fs
JOIN Transactions t ON fs.cc_num = t.cc_num
GROUP BY fs.cohort_month
ORDER BY fs.cohort_month;
-- INSIGHT: Cohorting by acquisition month shows whether customers who
--          joined in certain months are structurally more fraud-exposed -
--          a retention/onboarding-quality lens on fraud.


-- ---------------------------------------------------------------------
-- Q45. (Repeat victims) Which customers were defrauded more than once?
-- ---------------------------------------------------------------------
SELECT
    c.cc_num,
    CONCAT(c.first,' ',c.last)                   AS customer_name,
    SUM(t.is_fraud)                              AS fraud_incidents,
    ROUND(SUM(CASE WHEN t.is_fraud=1 THEN t.amt ELSE 0 END),2) AS total_fraud_loss
FROM Transactions t
JOIN Customers c ON t.cc_num = c.cc_num
GROUP BY c.cc_num, customer_name
HAVING fraud_incidents > 1
ORDER BY fraud_incidents DESC, total_fraud_loss DESC
LIMIT 20;
-- INSIGHT: Repeat victims are high-priority for card reissue / account
--          review. HAVING filters to customers hit 2+ times and ranks them
--          by both frequency and money lost.


-- ---------------------------------------------------------------------
-- Q46. (Velocity check) Customers with 3+ transactions inside any single
--      hour - a rapid-fire pattern typical of card testing.
-- ---------------------------------------------------------------------
SELECT
    cc_num,
    DATE_FORMAT(trans_date_trans_time, '%Y-%m-%d %H') AS txn_hour_bucket,
    COUNT(*)          AS txns_in_hour,
    SUM(is_fraud)     AS frauds_in_hour
FROM Transactions
GROUP BY cc_num, DATE_FORMAT(trans_date_trans_time, '%Y-%m-%d %H')
HAVING txns_in_hour >= 3
ORDER BY txns_in_hour DESC
LIMIT 25;
-- INSIGHT: Bucketing by customer + hour and keeping groups of 3+ surfaces
--          bursts of activity. High-velocity clusters are a strong,
--          real-time-friendly fraud indicator.
