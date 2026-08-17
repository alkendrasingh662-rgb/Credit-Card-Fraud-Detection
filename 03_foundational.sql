-- =====================================================================
-- FILE    : 03_foundational.sql
-- PURPOSE : Warm-up analytics - SELECT / WHERE / GROUP BY / HAVING /
--           ORDER BY, aggregate functions, and every JOIN type
--           (INNER, LEFT, RIGHT, SELF).
-- FORMAT  : Every query is written as
--             -- Qn. QUESTION (why we run it)
--             <the query>
--             -- INSIGHT: what the result tells us
-- =====================================================================

USE fraud_analytics;

-- ---------------------------------------------------------------------
-- Q1. What is the overall scale of fraud in the portfolio?
--     (total transactions, total frauds, and the fraud rate %)
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                   AS total_txns,
    SUM(is_fraud)                              AS total_frauds,
    ROUND(100 * SUM(is_fraud) / COUNT(*), 4)  AS fraud_rate_pct
FROM Transactions;
-- INSIGHT: Establishes the baseline. Fraud is a highly imbalanced class
--          (~0.5-0.6% of all transactions) - every later % is judged
--          against this baseline rate.


-- ---------------------------------------------------------------------
-- Q2. Which spending categories carry the most fraud, by count and rate?
-- ---------------------------------------------------------------------
SELECT
    m.category,
    COUNT(*)                                      AS total_txns,
    SUM(t.is_fraud)                               AS fraud_txns,
    ROUND(100 * SUM(t.is_fraud) / COUNT(*), 3)    AS fraud_rate_pct
FROM Transactions t
JOIN Merchants m ON t.merchant_id = m.merchant_id
GROUP BY m.category
ORDER BY fraud_rate_pct DESC;
-- INSIGHT: Ranks categories by risk. Online-style categories such as
--          shopping_net and grocery_pos usually top the fraud-rate list,
--          which is where monitoring effort should focus first.


-- ---------------------------------------------------------------------
-- Q3. Which categories are WORSE than the portfolio's average fraud rate?
--     (demonstrates HAVING to filter on an aggregate)
-- ---------------------------------------------------------------------
SELECT
    m.category,
    ROUND(100 * SUM(t.is_fraud) / COUNT(*), 3) AS fraud_rate_pct
FROM Transactions t
JOIN Merchants m ON t.merchant_id = m.merchant_id
GROUP BY m.category
HAVING fraud_rate_pct > (
        SELECT 100 * SUM(is_fraud) / COUNT(*) FROM Transactions
    )
ORDER BY fraud_rate_pct DESC;
-- INSIGHT: Isolates the "above-average risk" categories - a shortlist
--          for tighter rules, without hard-coding any threshold number.


-- ---------------------------------------------------------------------
-- Q4. What do the 10 largest transactions look like?
--     (WHERE-free ranking with ORDER BY + LIMIT)
-- ---------------------------------------------------------------------
SELECT trans_num, cc_num, amt, is_fraud, trans_date_trans_time
FROM Transactions
ORDER BY amt DESC
LIMIT 10;
-- INSIGHT: High-ticket transactions are disproportionately likely to be
--          fraudulent; a quick eyeball of is_fraud here shows whether the
--          biggest amounts skew fraudulent.


-- ---------------------------------------------------------------------
-- Q5. Do fraudulent transactions have a different average amount than
--     legitimate ones?
-- ---------------------------------------------------------------------
SELECT
    CASE WHEN is_fraud = 1 THEN 'Fraud' ELSE 'Legitimate' END AS txn_type,
    COUNT(*)             AS txns,
    ROUND(AVG(amt), 2)   AS avg_amount,
    ROUND(MAX(amt), 2)   AS max_amount,
    ROUND(MIN(amt), 2)   AS min_amount
FROM Transactions
GROUP BY is_fraud;
-- INSIGHT: Fraudulent transactions almost always show a much HIGHER
--          average amount - amount alone is a strong predictive signal.


-- ---------------------------------------------------------------------
-- Q6. Is fraud distributed differently across genders?
-- ---------------------------------------------------------------------
SELECT
    c.gender,
    COUNT(*)                                    AS total_txns,
    SUM(t.is_fraud)                             AS fraud_txns,
    ROUND(100 * SUM(t.is_fraud) / COUNT(*), 3)  AS fraud_rate_pct
FROM Transactions t
JOIN Customers c ON t.cc_num = c.cc_num
GROUP BY c.gender;
-- INSIGHT: Checks whether gender is associated with fraud exposure.
--          Usually the rates are close, telling us gender is a weak
--          predictor on its own.


-- =====================================================================
-- JOINS - all four types
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q7. (INNER JOIN) List fraudulent transactions with the customer's
--     full name and the merchant they hit.
-- ---------------------------------------------------------------------
SELECT
    t.trans_num,
    CONCAT(c.first, ' ', c.last) AS customer_name,
    m.merchant_name,
    m.category,
    t.amt,
    t.trans_date_trans_time
FROM Transactions t
INNER JOIN Customers c ON t.cc_num = c.cc_num
INNER JOIN Merchants m ON t.merchant_id = m.merchant_id
WHERE t.is_fraud = 1
ORDER BY t.amt DESC
LIMIT 20;
-- INSIGHT: The core investigative view - turns opaque IDs into a
--          human-readable fraud case list an analyst can act on.


-- ---------------------------------------------------------------------
-- Q8. (LEFT JOIN) Do we have any merchants that never recorded a single
--     transaction? (data-quality / coverage check)
-- ---------------------------------------------------------------------
SELECT
    m.merchant_id,
    m.merchant_name,
    COUNT(t.trans_num) AS txn_count
FROM Merchants m
LEFT JOIN Transactions t ON m.merchant_id = t.merchant_id
GROUP BY m.merchant_id, m.merchant_name
HAVING txn_count = 0;
-- INSIGHT: A LEFT JOIN keeps every merchant even with zero matches.
--          An empty result set here confirms every merchant is active
--          (good data integrity); any rows would flag orphan merchants.


-- ---------------------------------------------------------------------
-- Q9. (RIGHT JOIN) Same coverage idea, expressed from the transaction
--     side - confirm every transaction maps to a known merchant.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS txns_without_merchant
FROM Merchants m
RIGHT JOIN Transactions t ON m.merchant_id = t.merchant_id
WHERE m.merchant_id IS NULL;
-- INSIGHT: A RIGHT JOIN keeps every transaction. A count of 0 proves
--          referential integrity - no transaction points at a missing
--          merchant. (RIGHT JOIN is just a LEFT JOIN read backwards.)


-- ---------------------------------------------------------------------
-- Q10. Which customer JOBS have the highest fraud exposure?
-- ---------------------------------------------------------------------
SELECT
    c.job,
    COUNT(*)                                    AS total_txns,
    SUM(t.is_fraud)                             AS fraud_txns,
    ROUND(100 * SUM(t.is_fraud) / COUNT(*), 3)  AS fraud_rate_pct
FROM Transactions t
JOIN Customers c ON t.cc_num = c.cc_num
GROUP BY c.job
HAVING total_txns > 500          -- ignore tiny, noisy job groups
ORDER BY fraud_rate_pct DESC
LIMIT 15;
-- INSIGHT: Surfaces occupation segments with elevated fraud - useful
--          demographic context, filtered to statistically meaningful
--          group sizes with HAVING.


-- ---------------------------------------------------------------------
-- Q11. Which STATES see the most fraud?
-- ---------------------------------------------------------------------
SELECT
    c.state,
    COUNT(*)                                    AS total_txns,
    SUM(t.is_fraud)                             AS fraud_txns,
    ROUND(100 * SUM(t.is_fraud) / COUNT(*), 3)  AS fraud_rate_pct
FROM Transactions t
JOIN Customers c ON t.cc_num = c.cc_num
GROUP BY c.state
ORDER BY fraud_txns DESC
LIMIT 10;
-- INSIGHT: Geographic concentration of fraud - drives where regional
--          risk teams or state-level rules should be prioritised.


-- ---------------------------------------------------------------------
-- Q12. (SELF JOIN) Find pairs of customers who live in the same city and
--      state - a peer group used later for behavioural comparison.
-- ---------------------------------------------------------------------
SELECT
    a.city,
    a.state,
    CONCAT(a.first, ' ', a.last) AS customer_a,
    CONCAT(b.first, ' ', b.last) AS customer_b
FROM Customers a
JOIN Customers b
      ON a.city  = b.city
     AND a.state = b.state
     AND a.cc_num < b.cc_num       -- avoid self-pairing & mirror duplicates
ORDER BY a.state, a.city
LIMIT 20;
-- INSIGHT: A SELF JOIN relates a table to itself. The a.cc_num < b.cc_num
--          trick returns each pair once. This defines "local peers" for
--          spotting a customer whose behaviour deviates from their area.
