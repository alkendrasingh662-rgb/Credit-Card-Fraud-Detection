-- =====================================================================
-- FILE    : 02_load_data.sql
-- PURPOSE : Load the dataset into the staging table, then populate the
--           three normalized tables. Includes a full workaround for the
--           classic MySQL "secure_file_priv" error.
-- DATASET : data/fraud_data.csv  (included with this project - 100k rows).
--           Its columns match the Kaggle kartik2112/fraud-detection layout
--           exactly, so if you prefer the real ~1.3M-row data you can load
--           fraudTrain.csv + fraudTest.csv with the SAME statements below.
-- =====================================================================

USE fraud_analytics;

-- ---------------------------------------------------------------------
-- IMPORTANT - THE secure_file_priv PROBLEM (read before loading)
-- ---------------------------------------------------------------------
-- MySQL restricts where LOAD DATA INFILE can read files from. Check yours:
--
--     SHOW VARIABLES LIKE 'secure_file_priv';
--
-- You will get one of three results:
--   (a) A folder path  -> you can ONLY load files placed inside that folder.
--   (b) Empty string   -> you can load from anywhere.
--   (c) NULL           -> file import via LOAD DATA INFILE is DISABLED.
--
-- TWO WAYS TO SOLVE IT:
--
-- OPTION 1 (server-side, needs the folder):
--   Copy fraud_data.csv into the folder shown by secure_file_priv, then
--   use LOAD DATA INFILE (no LOCAL keyword). See BLOCK A below.
--
-- OPTION 2 (client-side, RECOMMENDED for Workbench):
--   Use LOAD DATA LOCAL INFILE - reads the file from YOUR machine, so the
--   secure_file_priv folder does not matter. It needs local_infile enabled
--   on BOTH server and client:
--     1. On server:  SET GLOBAL local_infile = 1;
--     2. In Workbench: Edit connection > Connection tab > Advanced >
--        add   OPT_LOCAL_INFILE=1   then reconnect.
--   See BLOCK B below.
-- ---------------------------------------------------------------------

SET GLOBAL local_infile = 1;   -- enable client-side loading (Option 2)


-- =====================================================================
-- BLOCK A : LOAD DATA INFILE  (server-side - use ONLY with Option 1)
-- Replace the path with your secure_file_priv folder + filename.
-- =====================================================================
/*
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/fraud_data.csv'
INTO TABLE stg_transactions
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(row_id, @trans_dt, cc_num, merchant, category, amt, first, last, gender,
 street, city, state, zip, lat, `long`, city_pop, job, @dob_str,
 trans_num, unix_time, merch_lat, merch_long, is_fraud)
SET trans_date_trans_time = STR_TO_DATE(@trans_dt, '%Y-%m-%d %H:%i:%s'),
    dob                   = STR_TO_DATE(@dob_str, '%Y-%m-%d');
*/


-- =====================================================================
-- BLOCK B : LOAD DATA LOCAL INFILE  (client-side - RECOMMENDED)
-- Point the path at wherever fraud_data.csv sits on your own laptop.
-- On Windows use forward slashes, e.g. 'C:/Users/Alkendra/Downloads/fraud_data.csv'
-- =====================================================================
LOAD DATA LOCAL INFILE 'C:/Users/Alkendra/Downloads/fraud_data.csv'
INTO TABLE stg_transactions
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(row_id, @trans_dt, cc_num, merchant, category, amt, first, last, gender,
 street, city, state, zip, lat, `long`, city_pop, job, @dob_str,
 trans_num, unix_time, merch_lat, merch_long, is_fraud)
SET trans_date_trans_time = STR_TO_DATE(@trans_dt, '%Y-%m-%d %H:%i:%s'),
    dob                   = STR_TO_DATE(@dob_str, '%Y-%m-%d');

-- (Using the real Kaggle data instead? Run the same block once per file -
--  once for fraudTrain.csv and once for fraudTest.csv - to reach ~1.3M rows.)

-- Sanity check the staging load:
SELECT COUNT(*) AS staged_rows FROM stg_transactions;


-- =====================================================================
-- STEP 4 : POPULATE THE NORMALIZED TABLES FROM STAGING
-- =====================================================================

-- 4a. CUSTOMERS
-- WHY : One row per unique cc_num. GROUP BY collapses the many
--       transaction rows of each customer down to a single profile row.
INSERT INTO Customers (cc_num, first, last, gender, street, city, state,
                       zip, lat, `long`, city_pop, job, dob)
SELECT cc_num, first, last, gender, street, city, state,
       zip, lat, `long`, city_pop, job, dob
FROM stg_transactions
GROUP BY cc_num, first, last, gender, street, city, state,
         zip, lat, `long`, city_pop, job, dob;

-- 4b. MERCHANTS
-- WHY : One row per unique merchant name. We strip the "fraud_" prefix
--       that the dataset attaches to every merchant name (it is a data
--       quirk, NOT an indicator of fraud) using REPLACE.
INSERT INTO Merchants (merchant_name, category)
SELECT DISTINCT
       REPLACE(merchant, 'fraud_', '') AS merchant_name,
       category
FROM stg_transactions;

-- 4c. TRANSACTIONS
-- WHY : The fact rows. We JOIN staging to Merchants (on the cleaned name)
--       to translate the merchant name into its surrogate merchant_id.
INSERT INTO Transactions (trans_num, cc_num, merchant_id,
                          trans_date_trans_time, unix_time, amt,
                          merch_lat, merch_long, is_fraud)
SELECT s.trans_num,
       s.cc_num,
       m.merchant_id,
       s.trans_date_trans_time,
       s.unix_time,
       s.amt,
       s.merch_lat,
       s.merch_long,
       s.is_fraud
FROM stg_transactions s
JOIN Merchants m
     ON REPLACE(s.merchant, 'fraud_', '') = m.merchant_name;

-- ---------------------------------------------------------------------
-- STEP 5 : VERIFY ROW COUNTS
-- WHAT WE EXPECT (with the included file):
--   Customers = 500 | Merchants = 200 | Transactions ~ 100,000
-- ---------------------------------------------------------------------
SELECT 'Customers'    AS table_name, COUNT(*) AS rows_loaded FROM Customers
UNION ALL
SELECT 'Merchants',    COUNT(*) FROM Merchants
UNION ALL
SELECT 'Transactions', COUNT(*) FROM Transactions;

-- Optional: once you have confirmed the counts, you can drop staging.
-- DROP TABLE stg_transactions;
