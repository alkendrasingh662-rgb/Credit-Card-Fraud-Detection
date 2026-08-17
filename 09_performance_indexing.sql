-- =====================================================================
-- FILE    : 09_performance_indexing.sql
-- PURPOSE : Query performance - reading EXPLAIN plans, adding indexes,
--           and proving the speed-up. With ~1.3M transaction rows these
--           effects are real and measurable, not theoretical.
-- =====================================================================

USE fraud_analytics;

-- ---------------------------------------------------------------------
-- Q53. (EXPLAIN - before) Look at the plan for a common lookup: all
--      transactions for one customer. Without an index this is a full
--      table scan.
-- ---------------------------------------------------------------------
EXPLAIN
SELECT * FROM Transactions
WHERE cc_num = 4396091624673316;
-- INSIGHT: Read the "type" and "rows" columns. type = ALL means a full
--          scan; rows ~ 1.3M means MySQL expects to examine every row.
--          That is the cost we are about to remove.


-- ---------------------------------------------------------------------
-- Q54. (CREATE INDEX) Add the indexes that support our most frequent
--      access patterns: by customer, by merchant, by date.
-- ---------------------------------------------------------------------
CREATE INDEX idx_txn_cc_num      ON Transactions (cc_num);
CREATE INDEX idx_txn_merchant    ON Transactions (merchant_id);
CREATE INDEX idx_txn_date        ON Transactions (trans_date_trans_time);
CREATE INDEX idx_txn_is_fraud    ON Transactions (is_fraud);
-- INSIGHT: An index is a sorted lookup structure (B-tree). These four cover
--          the columns we filter and join on most. Note the trade-off:
--          indexes speed up reads but slightly slow down inserts/updates
--          and use extra disk.


-- ---------------------------------------------------------------------
-- Q55. (EXPLAIN - after) Re-check the same customer lookup. It should now
--      use the index instead of scanning the whole table.
-- ---------------------------------------------------------------------
EXPLAIN
SELECT * FROM Transactions
WHERE cc_num = 4396091624673316;
-- INSIGHT: type should change from ALL to ref, key should show
--          idx_txn_cc_num, and rows should drop from ~1.3M to a few hundred.
--          Same query, a fraction of the work - the whole point of indexing.


-- ---------------------------------------------------------------------
-- Q56. (Composite index) A date-range + fraud filter is common. A
--      composite index on (is_fraud, trans_date_trans_time) serves it in
--      one structure.
-- ---------------------------------------------------------------------
CREATE INDEX idx_fraud_date ON Transactions (is_fraud, trans_date_trans_time);

EXPLAIN
SELECT COUNT(*), SUM(amt)
FROM Transactions
WHERE is_fraud = 1
  AND trans_date_trans_time BETWEEN '2019-06-01' AND '2019-06-30';
-- INSIGHT: Column order in a composite index matters - the most selective /
--          equality column (is_fraud) comes first, then the range column
--          (date). MySQL can satisfy both predicates from this one index.


-- ---------------------------------------------------------------------
-- Q57. (Inspect indexes) List every index now on the Transactions table.
-- ---------------------------------------------------------------------
SHOW INDEX FROM Transactions;
-- INSIGHT: Confirms which indexes exist (name, columns, cardinality).
--          High cardinality = many distinct values = a more useful index.
--          Good final check that the tuning above was applied.
