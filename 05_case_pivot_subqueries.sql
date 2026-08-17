-- =====================================================================
-- FILE    : 05_case_pivot_subqueries.sql
-- PURPOSE : Conditional logic (CASE WHEN), PIVOT via conditional
--           aggregation (MySQL has no native PIVOT), and subqueries
--           (nested, in-FROM derived tables, and correlated).
-- =====================================================================

USE fraud_analytics;

-- =====================================================================
-- CASE WHEN
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q22. Bucket every transaction into an amount tier and see how fraud
--      concentrates across tiers.
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN amt < 10    THEN '1) < $10'
        WHEN amt < 50    THEN '2) $10-49'
        WHEN amt < 200   THEN '3) $50-199'
        WHEN amt < 1000  THEN '4) $200-999'
        ELSE                  '5) $1000+'
    END                                          AS amount_tier,
    COUNT(*)                                     AS total_txns,
    SUM(is_fraud)                               AS fraud_txns,
    ROUND(100 * SUM(is_fraud) / COUNT(*), 3)    AS fraud_rate_pct
FROM Transactions
GROUP BY amount_tier
ORDER BY amount_tier;
-- INSIGHT: CASE turns a continuous amount into labelled tiers. Fraud rate
--          climbs sharply in the highest tier - big-ticket transactions
--          are far riskier per transaction.


-- =====================================================================
-- PIVOT (via conditional aggregation - the MySQL way)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q23. Build a category-by-quarter fraud matrix: one row per category,
--      one column per quarter. (This is what "PIVOT" means in MySQL.)
-- ---------------------------------------------------------------------
SELECT
    m.category,
    SUM(CASE WHEN QUARTER(t.trans_date_trans_time)=1 THEN t.is_fraud ELSE 0 END) AS q1_fraud,
    SUM(CASE WHEN QUARTER(t.trans_date_trans_time)=2 THEN t.is_fraud ELSE 0 END) AS q2_fraud,
    SUM(CASE WHEN QUARTER(t.trans_date_trans_time)=3 THEN t.is_fraud ELSE 0 END) AS q3_fraud,
    SUM(CASE WHEN QUARTER(t.trans_date_trans_time)=4 THEN t.is_fraud ELSE 0 END) AS q4_fraud
FROM Transactions t
JOIN Merchants m ON t.merchant_id = m.merchant_id
GROUP BY m.category
ORDER BY SUM(t.is_fraud) DESC;
-- INSIGHT: SUM(CASE...) rotates rows into columns - the classic MySQL
--          PIVOT. Instantly shows whether any category's fraud is
--          seasonal (spikes in one quarter).


-- ---------------------------------------------------------------------
-- Q24. Pivot transaction counts: gender (rows) x amount tier (columns).
-- ---------------------------------------------------------------------
SELECT
    c.gender,
    SUM(CASE WHEN t.amt < 50   THEN 1 ELSE 0 END) AS tier_under_50,
    SUM(CASE WHEN t.amt >= 50  AND t.amt < 200 THEN 1 ELSE 0 END) AS tier_50_199,
    SUM(CASE WHEN t.amt >= 200 THEN 1 ELSE 0 END) AS tier_200_plus,
    COUNT(*) AS total
FROM Transactions t
JOIN Customers c ON t.cc_num = c.cc_num
GROUP BY c.gender;
-- INSIGHT: A two-dimensional summary in a single scan - compares male vs
--          female spending distribution across amount tiers without three
--          separate queries.


-- =====================================================================
-- SUBQUERIES
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q25. (Nested / non-correlated) Which transactions are larger than the
--      overall average transaction amount?
-- ---------------------------------------------------------------------
SELECT trans_num, cc_num, amt, is_fraud
FROM Transactions
WHERE amt > (SELECT AVG(amt) FROM Transactions)
ORDER BY amt DESC
LIMIT 20;
-- INSIGHT: The inner query runs once and returns a single number; the
--          outer query filters against it. A simple "above average" gate.


-- ---------------------------------------------------------------------
-- Q26. (Correlated) Which transactions exceed the individual customer's
--      OWN average spend? (personalised anomaly, not a global threshold)
-- ---------------------------------------------------------------------
SELECT
    t.trans_num,
    t.cc_num,
    t.amt,
    t.is_fraud
FROM Transactions t
WHERE t.amt > (
        SELECT AVG(t2.amt)
        FROM Transactions t2
        WHERE t2.cc_num = t.cc_num      -- correlation: inner depends on outer row
    )
  AND t.is_fraud = 1
ORDER BY t.amt DESC
LIMIT 20;
-- INSIGHT: A correlated subquery re-evaluates per customer, so "large" is
--          relative to that person's normal behaviour - a much stronger
--          fraud signal than one flat threshold.


-- ---------------------------------------------------------------------
-- Q27. (Correlated) Which merchants have a fraud rate above the average
--      fraud rate of their OWN category?
-- ---------------------------------------------------------------------
SELECT
    m.merchant_name,
    m.category,
    ROUND(100 * SUM(t.is_fraud)/COUNT(*), 3) AS merchant_fraud_rate
FROM Transactions t
JOIN Merchants m ON t.merchant_id = m.merchant_id
GROUP BY m.merchant_id, m.merchant_name, m.category
HAVING merchant_fraud_rate > (
        SELECT 100 * SUM(t2.is_fraud)/COUNT(*)
        FROM Transactions t2
        JOIN Merchants m2 ON t2.merchant_id = m2.merchant_id
        WHERE m2.category = m.category      -- compare each merchant to its category
    )
ORDER BY merchant_fraud_rate DESC
LIMIT 20;
-- INSIGHT: Flags merchants that are risk outliers *within their peer
--          category* - fairer than comparing a gas station to an online
--          store on one global number.


-- ---------------------------------------------------------------------
-- Q28. (Subquery in FROM) Rank customers by total spend using a derived
--      table, then keep only the top spenders.
-- ---------------------------------------------------------------------
SELECT customer_name, total_spend, txn_count
FROM (
    SELECT
        c.cc_num,
        CONCAT(c.first,' ',c.last)  AS customer_name,
        ROUND(SUM(t.amt),2)         AS total_spend,
        COUNT(*)                    AS txn_count
    FROM Transactions t
    JOIN Customers c ON t.cc_num = c.cc_num
    GROUP BY c.cc_num, customer_name
) AS spend_summary
WHERE total_spend > 50000
ORDER BY total_spend DESC
LIMIT 15;
-- INSIGHT: A derived table (subquery in FROM) lets us aggregate first,
--          then filter/sort the aggregated result - something WHERE
--          cannot do directly on an aggregate.
