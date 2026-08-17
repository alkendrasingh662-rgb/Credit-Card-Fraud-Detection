# Credit Card Fraud Detection — SQL Analytics

An end-to-end SQL analytics project on a credit-card transactions dataset (schema matches the [Kaggle kartik2112](https://www.kaggle.com/datasets/kartik2112/fraud-detection) layout). Built and tested on **MySQL 8.0 / MySQL Workbench**. **A ready-to-load dataset is included** in `data/fraud_data.csv` (100,000 transactions, 500 customers, 200 merchants) — no download required.

Every query has been executed and verified end-to-end. The project takes a flat, denormalized CSV, models it into a clean **3-table normalized schema**, and then answers real fraud-analytics questions with **57 documented queries** covering the full SQL surface area — from basic joins to window functions, recursive CTEs, stored procedures, transactions (ACID), and index tuning.

Every query follows the same format:
1. **Question** — *why* we are writing the query (the business reason)
2. **The query**
3. **Insight** — *what* the result tells us

---

## Dataset

Included: **`data/fraud_data.csv`** — 100,000 synthetic transactions with realistic, query-friendly fraud signals baked in (fraud amounts skew high, cluster at night, sit farther from the cardholder's home, hit certain categories, and include repeat victims and velocity bursts). Column layout is identical to the Kaggle `kartik2112/fraud-detection` set, so you can swap in the real ~1.3M-row data (`fraudTrain.csv` + `fraudTest.csv`) with the same load script if you wish.

| | |
|---|---|
| Rows | 100,000 transactions |
| Entities | 500 customers, 200 merchants |
| Grain | One row per credit-card transaction |
| Target | `is_fraud` (0 = legitimate, 1 = fraud) |
| Fraud rate | ~0.8% (imbalanced, like real fraud) |

## How to run

1. Run **`sql/01_schema.sql`** — creates the database, staging table, and the 3 normalized tables.
2. Put `data/fraud_data.csv` somewhere on your machine and set the path in **`sql/02_load_data.sql`** (Block B). Run it. **Read the `secure_file_priv` notes at the top** if `LOAD DATA` errors out.
3. Run the query files in order (`03` → `09`). Each is self-contained.

## File guide

| File | Topics covered |
|---|---|
| `01_schema.sql` | Database, staging table, normalized tables, PK/FK constraints |
| `02_load_data.sql` | `LOAD DATA` (both `INFILE` and `LOCAL INFILE`), `secure_file_priv` fix, normalization inserts |
| `03_foundational.sql` | SELECT/WHERE/GROUP BY/HAVING/ORDER BY, aggregates, INNER/LEFT/RIGHT/SELF joins |
| `04_string_date_null.sql` | String functions, date/time functions, NULL handling (COALESCE, IFNULL, NULLIF) |
| `05_case_pivot_subqueries.sql` | CASE WHEN, PIVOT via conditional aggregation, nested & correlated subqueries |
| `06_window_functions.sql` | ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD, FIRST_VALUE/LAST_VALUE, running totals, moving averages |
| `07_ctes_advanced_analytics.sql` | Simple/chained/recursive CTEs, haversine distance, z-score anomaly, cohort analysis, velocity checks |
| `08_views_procedures_transactions.sql` | Views, stored procedures (IN/OUT params), transactions (COMMIT/ROLLBACK) |
| `09_performance_indexing.sql` | EXPLAIN plans, single & composite indexes, before/after tuning |

## Key techniques demonstrated

- Normalization / ETL from a flat file into a star-like schema
- All four JOIN types including SELF JOIN
- Full window-function suite (MySQL 8.0)
- Recursive CTEs (date-series gap filling)
- Views and parameterized stored procedures
- Transaction control and ACID (COMMIT / ROLLBACK)
- Index design and EXPLAIN-driven performance tuning
- Applied analytics: haversine geo-distance, per-customer z-score anomaly detection, cohort analysis, transaction velocity

## Author

**Alkendra** — Data / Business Analyst
