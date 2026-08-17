-- =====================================================================
-- FILE    : 08_views_procedures_transactions.sql
-- PURPOSE : Database objects - VIEWS, STORED PROCEDURES, and explicit
--           TRANSACTIONS (COMMIT / ROLLBACK, the ACID demo).
-- NOTE    : In MySQL Workbench, run each CREATE PROCEDURE block on its own
--           (the DELIMITER lines handle the ; inside the procedure body).
-- =====================================================================

USE fraud_analytics;

-- =====================================================================
-- VIEWS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q47. (VIEW) A reusable daily fraud summary so dashboards/queries never
--      repeat the aggregation logic.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_daily_fraud_summary AS
SELECT
    DATE(trans_date_trans_time)                 AS txn_date,
    COUNT(*)                                     AS total_txns,
    SUM(is_fraud)                               AS fraud_txns,
    ROUND(100 * SUM(is_fraud)/COUNT(*), 3)      AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud=1 THEN amt ELSE 0 END),2) AS fraud_loss
FROM Transactions
GROUP BY DATE(trans_date_trans_time);

-- use it like a table:
SELECT * FROM v_daily_fraud_summary ORDER BY fraud_loss DESC LIMIT 10;
-- INSIGHT: A VIEW stores the query, not the data. Anyone can now
--          "SELECT * FROM v_daily_fraud_summary" without rewriting the
--          aggregation - one source of truth for daily fraud numbers.


-- ---------------------------------------------------------------------
-- Q48. (VIEW) A high-risk customer view - customers with any fraud,
--      ready to feed a review queue.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_high_risk_customers AS
SELECT
    c.cc_num,
    CONCAT(c.first,' ',c.last)                   AS customer_name,
    c.state,
    COUNT(*)                                     AS total_txns,
    SUM(t.is_fraud)                              AS fraud_txns,
    ROUND(SUM(CASE WHEN t.is_fraud=1 THEN t.amt ELSE 0 END),2) AS fraud_loss
FROM Customers c
JOIN Transactions t ON c.cc_num = t.cc_num
GROUP BY c.cc_num, customer_name, c.state
HAVING fraud_txns > 0;

SELECT * FROM v_high_risk_customers ORDER BY fraud_loss DESC LIMIT 10;
-- INSIGHT: Encapsulates the "who to investigate" logic. The review team
--          queries a clean, named object instead of a 10-line aggregate.


-- =====================================================================
-- STORED PROCEDURES
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q49. (Stored Procedure) Parameterised fraud report for any date range.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_fraud_report_by_daterange;
DELIMITER $$
CREATE PROCEDURE sp_fraud_report_by_daterange(
    IN p_start_date DATE,
    IN p_end_date   DATE
)
BEGIN
    SELECT
        m.category,
        COUNT(*)                                    AS total_txns,
        SUM(t.is_fraud)                             AS fraud_txns,
        ROUND(100 * SUM(t.is_fraud)/COUNT(*), 3)    AS fraud_rate_pct,
        ROUND(SUM(CASE WHEN t.is_fraud=1 THEN t.amt ELSE 0 END),2) AS fraud_loss
    FROM Transactions t
    JOIN Merchants m ON t.merchant_id = m.merchant_id
    WHERE t.trans_date_trans_time >= p_start_date
      AND t.trans_date_trans_time <  p_end_date + INTERVAL 1 DAY
    GROUP BY m.category
    ORDER BY fraud_loss DESC;
END $$
DELIMITER ;

-- call it:
CALL sp_fraud_report_by_daterange('2019-01-01', '2019-03-31');
-- INSIGHT: A stored procedure packages parameterised logic on the server.
--          Analysts just CALL it with two dates - no need to hand-edit the
--          query, and the logic stays consistent for everyone.


-- ---------------------------------------------------------------------
-- Q50. (Stored Procedure with OUT param) Return the total fraud loss for
--      a single category into an output variable.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_category_fraud_loss;
DELIMITER $$
CREATE PROCEDURE sp_category_fraud_loss(
    IN  p_category   VARCHAR(60),
    OUT p_total_loss DECIMAL(14,2)
)
BEGIN
    SELECT SUM(CASE WHEN t.is_fraud=1 THEN t.amt ELSE 0 END)
      INTO p_total_loss
    FROM Transactions t
    JOIN Merchants m ON t.merchant_id = m.merchant_id
    WHERE m.category = p_category;
END $$
DELIMITER ;

-- call it and read the OUT value:
CALL sp_category_fraud_loss('shopping_net', @loss);
SELECT @loss AS shopping_net_fraud_loss;
-- INSIGHT: OUT parameters let a procedure hand a computed scalar back to
--          the caller - handy when the result feeds another step rather
--          than being displayed directly.


-- =====================================================================
-- TRANSACTIONS (ACID: COMMIT / ROLLBACK)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q51. (ROLLBACK) A transaction was wrongly flagged as fraud. Start a
--      transaction, correct it, inspect, then ROLL BACK to undo the change
--      - proving changes are not permanent until committed.
-- ---------------------------------------------------------------------
START TRANSACTION;

UPDATE Transactions
SET is_fraud = 0
WHERE trans_num = (SELECT trans_num FROM (
        SELECT trans_num FROM Transactions WHERE is_fraud = 1 LIMIT 1
     ) x);

-- check the change is visible INSIDE the transaction:
SELECT trans_num, is_fraud
FROM Transactions
WHERE is_fraud = 0
ORDER BY trans_num
LIMIT 1;

ROLLBACK;   -- undo everything since START TRANSACTION
-- INSIGHT: ROLLBACK discards uncommitted work - the row reverts to
--          is_fraud=1. This demonstrates Atomicity: nothing is saved until
--          COMMIT, so a mistake mid-operation costs nothing.


-- ---------------------------------------------------------------------
-- Q52. (COMMIT) The correct way to make a genuine, permanent correction.
-- ---------------------------------------------------------------------
START TRANSACTION;

-- (Example: mark a confirmed legitimate transaction. Adjust the WHERE to a
--  real trans_num you have verified before running for real.)
UPDATE Transactions
SET is_fraud = 0
WHERE trans_num = 'PUT_A_VERIFIED_TRANS_NUM_HERE';

COMMIT;     -- make it permanent
-- INSIGHT: COMMIT persists the change so it survives disconnects/restarts
--          (Durability). START TRANSACTION + COMMIT is the safe pattern for
--          any manual data correction - you get a chance to verify, and can
--          ROLLBACK instead if something looks wrong.
