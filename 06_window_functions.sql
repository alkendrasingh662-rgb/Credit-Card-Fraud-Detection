-- =====================================================================
-- FILE    : 06_window_functions.sql
-- PURPOSE : Window functions (MySQL 8.0+): ROW_NUMBER, RANK, DENSE_RANK,
--           NTILE, LAG, LEAD, FIRST_VALUE, LAST_VALUE, running totals,
--           moving averages, and share-of-total.
-- =====================================================================

USE fraud_analytics;

-- ---------------------------------------------------------------------
-- Q29. (ROW_NUMBER) Get the single MOST RECENT transaction per customer.
-- ---------------------------------------------------------------------
SELECT *
FROM (
    SELECT
        t.cc_num,
        t.trans_num,
        t.amt,
        t.trans_date_trans_time,
        ROW_NUMBER() OVER (
            PARTITION BY t.cc_num
            ORDER BY t.trans_date_trans_time DESC
        ) AS rn
    FROM Transactions t
) ranked
WHERE rn = 1
LIMIT 20;
-- INSIGHT: ROW_NUMBER numbers rows within each customer partition; rn=1
--          picks each customer's latest activity - the classic
--          "top-N-per-group" / most-recent-record pattern.


-- ---------------------------------------------------------------------
-- Q30. (RANK vs DENSE_RANK) Rank merchants by total fraud count and see
--      how the two ranking functions treat ties differently.
-- ---------------------------------------------------------------------
SELECT
    m.merchant_name,
    SUM(t.is_fraud)                                       AS fraud_count,
    RANK()       OVER (ORDER BY SUM(t.is_fraud) DESC)     AS rnk,
    DENSE_RANK() OVER (ORDER BY SUM(t.is_fraud) DESC)     AS dense_rnk
FROM Transactions t
JOIN Merchants m ON t.merchant_id = m.merchant_id
GROUP BY m.merchant_id, m.merchant_name
ORDER BY fraud_count DESC
LIMIT 20;
-- INSIGHT: RANK leaves gaps after ties (1,1,3), DENSE_RANK does not
--          (1,1,2). Shows the worst-offending merchants for a block-list.


-- ---------------------------------------------------------------------
-- Q31. (NTILE) Split customers into 10 spend deciles for risk tiering.
-- ---------------------------------------------------------------------
SELECT
    cc_num,
    total_spend,
    NTILE(10) OVER (ORDER BY total_spend DESC) AS spend_decile
FROM (
    SELECT cc_num, SUM(amt) AS total_spend
    FROM Transactions
    GROUP BY cc_num
) s
ORDER BY spend_decile, total_spend DESC
LIMIT 30;
-- INSIGHT: NTILE(10) divides customers into ten equal groups. Decile 1 =
--          the biggest spenders (highest financial exposure) - a ready
--          segmentation for tiered monitoring.


-- ---------------------------------------------------------------------
-- Q32. (LAG) For each customer, compare every transaction amount to their
--      PREVIOUS transaction - detect sudden jumps.
-- ---------------------------------------------------------------------
SELECT
    cc_num,
    trans_date_trans_time,
    amt,
    LAG(amt) OVER (PARTITION BY cc_num ORDER BY trans_date_trans_time) AS prev_amt,
    amt - LAG(amt) OVER (PARTITION BY cc_num ORDER BY trans_date_trans_time) AS amt_change
FROM Transactions
WHERE cc_num = (SELECT cc_num FROM Transactions LIMIT 1)   -- one customer for readability
ORDER BY trans_date_trans_time
LIMIT 30;
-- INSIGHT: LAG pulls the prior row's value into the current row. A large
--          positive amt_change (a spend spike right after small buys) is a
--          textbook fraud pattern.


-- ---------------------------------------------------------------------
-- Q33. (LEAD) Measure the time gap (in minutes) to each customer's NEXT
--      transaction - a velocity signal.
-- ---------------------------------------------------------------------
SELECT
    cc_num,
    trans_date_trans_time,
    LEAD(trans_date_trans_time) OVER (
        PARTITION BY cc_num ORDER BY trans_date_trans_time
    ) AS next_txn_time,
    TIMESTAMPDIFF(
        MINUTE,
        trans_date_trans_time,
        LEAD(trans_date_trans_time) OVER (
            PARTITION BY cc_num ORDER BY trans_date_trans_time)
    ) AS mins_to_next
FROM Transactions
WHERE cc_num = (SELECT cc_num FROM Transactions LIMIT 1)
ORDER BY trans_date_trans_time
LIMIT 30;
-- INSIGHT: LEAD looks forward to the next row. Very small mins_to_next
--          (several purchases within minutes) indicates card-testing /
--          rapid-fire fraud.


-- ---------------------------------------------------------------------
-- Q34. (FIRST_VALUE / LAST_VALUE) Show each customer's first-ever and
--      most-recent transaction amount side by side.
-- ---------------------------------------------------------------------
SELECT DISTINCT
    cc_num,
    FIRST_VALUE(amt) OVER w AS first_txn_amt,
    LAST_VALUE(amt)  OVER w AS latest_txn_amt
FROM Transactions
WINDOW w AS (
    PARTITION BY cc_num
    ORDER BY trans_date_trans_time
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
LIMIT 20;
-- INSIGHT: LAST_VALUE needs the full-frame clause (UNBOUNDED ... FOLLOWING)
--          or it only "sees" up to the current row. Compares onboarding
--          behaviour vs current behaviour per customer.


-- ---------------------------------------------------------------------
-- Q35. (Running total) Cumulative fraud LOSS over time (daily).
-- ---------------------------------------------------------------------
SELECT
    txn_date,
    daily_fraud_amt,
    SUM(daily_fraud_amt) OVER (ORDER BY txn_date) AS cumulative_fraud_amt
FROM (
    SELECT
        DATE(trans_date_trans_time)            AS txn_date,
        SUM(CASE WHEN is_fraud=1 THEN amt ELSE 0 END) AS daily_fraud_amt
    FROM Transactions
    GROUP BY DATE(trans_date_trans_time)
) d
ORDER BY txn_date
LIMIT 40;
-- INSIGHT: SUM() OVER (ORDER BY date) accumulates day by day - the running
--          total of money lost to fraud, exactly the curve a finance team
--          tracks.


-- ---------------------------------------------------------------------
-- Q36. (Moving average) 7-day moving average of daily fraud count to
--      smooth out day-to-day noise.
-- ---------------------------------------------------------------------
SELECT
    txn_date,
    daily_fraud_cnt,
    ROUND(AVG(daily_fraud_cnt) OVER (
        ORDER BY txn_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7d
FROM (
    SELECT
        DATE(trans_date_trans_time) AS txn_date,
        SUM(is_fraud)               AS daily_fraud_cnt
    FROM Transactions
    GROUP BY DATE(trans_date_trans_time)
) d
ORDER BY txn_date
LIMIT 40;
-- INSIGHT: A framed AVG() over the trailing 7 rows smooths spiky daily
--          counts into a trend line - standard for detecting a genuine
--          upward drift vs random noise.


-- ---------------------------------------------------------------------
-- Q37. (Share of total) Each category's percentage share of ALL fraud.
-- ---------------------------------------------------------------------
SELECT
    m.category,
    SUM(t.is_fraud) AS fraud_txns,
    ROUND(100 * SUM(t.is_fraud)
              / SUM(SUM(t.is_fraud)) OVER (), 2) AS pct_of_all_fraud
FROM Transactions t
JOIN Merchants m ON t.merchant_id = m.merchant_id
GROUP BY m.category
ORDER BY fraud_txns DESC;
-- INSIGHT: SUM(SUM(...)) OVER () gives the grand total as a window over the
--          grouped rows, so each category's fraud is expressed as a % of
--          the whole - a Pareto view of where fraud volume lives.
