-- =====================================================================
-- FILE    : 04_string_date_null.sql
-- PURPOSE : String functions, Date/Time functions, and NULL handling
--           (COALESCE, IFNULL, NULLIF).
-- =====================================================================

USE fraud_analytics;

-- =====================================================================
-- STRING FUNCTIONS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q13. Build a clean customer directory: full name (proper case),
--      initials, and the length of the full name.
-- ---------------------------------------------------------------------
SELECT
    cc_num,
    CONCAT(first, ' ', last)                       AS full_name,
    CONCAT(UPPER(LEFT(first,1)), UPPER(LEFT(last,1))) AS initials,
    CHAR_LENGTH(CONCAT(first, ' ', last))          AS name_length
FROM Customers
LIMIT 15;
-- INSIGHT: Demonstrates CONCAT, UPPER, LEFT, CHAR_LENGTH to reshape raw
--          name fields into report-ready strings - the kind of tidy
--          output a dashboard or export needs.


-- ---------------------------------------------------------------------
-- Q14. Confirm the "fraud_" prefix was stripped correctly, and show the
--      cleaned merchant name in upper case for a report header.
-- ---------------------------------------------------------------------
SELECT
    merchant_id,
    merchant_name,
    UPPER(merchant_name)                    AS display_name,
    SUBSTRING(merchant_name, 1, 10)         AS short_name
FROM Merchants
LIMIT 15;
-- INSIGHT: Verifies the REPLACE cleaning done at load time and shows
--          SUBSTRING for truncating long merchant names in tight UI space.


-- =====================================================================
-- DATE / TIME FUNCTIONS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q15. How old is each customer, and how does fraud rate vary by age band?
-- ---------------------------------------------------------------------
SELECT
    age_band,
    COUNT(*)                                    AS total_txns,
    SUM(is_fraud)                               AS fraud_txns,
    ROUND(100 * SUM(is_fraud) / COUNT(*), 3)    AS fraud_rate_pct
FROM (
    SELECT
        t.is_fraud,
        CASE
            WHEN TIMESTAMPDIFF(YEAR, c.dob, t.trans_date_trans_time) < 30 THEN '1) Under 30'
            WHEN TIMESTAMPDIFF(YEAR, c.dob, t.trans_date_trans_time) < 45 THEN '2) 30-44'
            WHEN TIMESTAMPDIFF(YEAR, c.dob, t.trans_date_trans_time) < 60 THEN '3) 45-59'
            ELSE '4) 60+'
        END AS age_band
    FROM Transactions t
    JOIN Customers c ON t.cc_num = c.cc_num
) AS aged
GROUP BY age_band
ORDER BY age_band;
-- INSIGHT: TIMESTAMPDIFF computes age at transaction time. Reveals which
--          age groups are targeted most - often older cardholders show a
--          higher fraud rate.


-- ---------------------------------------------------------------------
-- Q16. At what HOUR of day does fraud peak?
-- ---------------------------------------------------------------------
SELECT
    HOUR(trans_date_trans_time)                 AS txn_hour,
    COUNT(*)                                     AS total_txns,
    SUM(is_fraud)                               AS fraud_txns,
    ROUND(100 * SUM(is_fraud) / COUNT(*), 3)    AS fraud_rate_pct
FROM Transactions
GROUP BY HOUR(trans_date_trans_time)
ORDER BY fraud_rate_pct DESC;
-- INSIGHT: HOUR() exposes the time-of-day signature. Fraud famously
--          spikes in the late-night / early-morning hours (roughly
--          22:00-03:00) when victims are asleep.


-- ---------------------------------------------------------------------
-- Q17. Which DAY OF WEEK carries the most fraud?
-- ---------------------------------------------------------------------
SELECT
    DAYNAME(trans_date_trans_time)              AS weekday,
    COUNT(*)                                    AS total_txns,
    SUM(is_fraud)                               AS fraud_txns,
    ROUND(100 * SUM(is_fraud) / COUNT(*), 3)    AS fraud_rate_pct
FROM Transactions
GROUP BY DAYNAME(trans_date_trans_time), DAYOFWEEK(trans_date_trans_time)
ORDER BY DAYOFWEEK(trans_date_trans_time);
-- INSIGHT: DAYNAME() gives a weekly pattern; DAYOFWEEK is used in ORDER BY
--          so the days come out Sun->Sat rather than alphabetically.


-- ---------------------------------------------------------------------
-- Q18. What is the monthly fraud trend across the dataset?
-- ---------------------------------------------------------------------
SELECT
    DATE_FORMAT(trans_date_trans_time, '%Y-%m')  AS ym,
    COUNT(*)                                     AS total_txns,
    SUM(is_fraud)                                AS fraud_txns,
    ROUND(100 * SUM(is_fraud) / COUNT(*), 3)     AS fraud_rate_pct
FROM Transactions
GROUP BY DATE_FORMAT(trans_date_trans_time, '%Y-%m')
ORDER BY ym;
-- INSIGHT: DATE_FORMAT buckets to month. This is the headline trend line
--          - is fraud rising, falling, or seasonal over the period?


-- =====================================================================
-- NULL HANDLING
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q19. (COALESCE) Show customers, replacing any missing job with a
--      readable placeholder so reports never display blank cells.
-- ---------------------------------------------------------------------
SELECT
    cc_num,
    CONCAT(first, ' ', last)          AS customer_name,
    COALESCE(NULLIF(TRIM(job), ''), 'Not Provided') AS job_clean
FROM Customers
LIMIT 20;
-- INSIGHT: COALESCE returns the first non-NULL value; wrapping NULLIF
--          around TRIM(job) also converts empty strings '' into NULL
--          first, so both blanks AND nulls become 'Not Provided'.


-- ---------------------------------------------------------------------
-- Q20. (NULLIF) Safely compute fraud rate per state WITHOUT risking a
--      divide-by-zero error.
-- ---------------------------------------------------------------------
SELECT
    c.state,
    SUM(t.is_fraud)                                            AS fraud_txns,
    COUNT(*)                                                   AS total_txns,
    ROUND(100 * SUM(t.is_fraud) / NULLIF(COUNT(*), 0), 3)     AS fraud_rate_pct
FROM Transactions t
JOIN Customers c ON t.cc_num = c.cc_num
GROUP BY c.state
ORDER BY fraud_rate_pct DESC
LIMIT 10;
-- INSIGHT: NULLIF(COUNT(*),0) turns a zero denominator into NULL, so the
--          division yields NULL instead of throwing an error - a defensive
--          pattern for any computed ratio.


-- ---------------------------------------------------------------------
-- Q21. (IFNULL) Produce a per-customer fraud summary where customers who
--      have never been defrauded still show 0, not a blank.
-- ---------------------------------------------------------------------
SELECT
    c.cc_num,
    CONCAT(c.first, ' ', c.last)     AS customer_name,
    IFNULL(SUM(t.is_fraud), 0)       AS fraud_txns
FROM Customers c
LEFT JOIN Transactions t ON c.cc_num = t.cc_num
GROUP BY c.cc_num, customer_name
ORDER BY fraud_txns DESC
LIMIT 15;
-- INSIGHT: IFNULL(x,0) guarantees a numeric result even for customers
--          with no matching (or no fraudulent) transactions - keeps the
--          summary clean and chart-ready.
