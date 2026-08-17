-- =====================================================================
-- PROJECT : Credit Card Fraud Detection - SQL Analytics
-- FILE    : 01_schema.sql
-- PURPOSE : Create the database and a normalized 3-table schema
--           (Customers, Merchants, Transactions) from the flat
--           Kaggle "Credit Card Transactions Fraud Detection" dataset.
-- ENGINE  : MySQL 8.0+ (tested on MySQL Workbench)
-- AUTHOR  : Alkendra
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1 : Create and select the database
-- ---------------------------------------------------------------------
DROP DATABASE IF EXISTS fraud_analytics;
CREATE DATABASE fraud_analytics;
USE fraud_analytics;


-- ---------------------------------------------------------------------
-- STEP 2 : STAGING TABLE
-- WHY  : The Kaggle CSV is a single wide (denormalized) file. We first
--        load it AS-IS into a staging table, then split it into three
--        clean, normalized tables. This is standard ETL practice and
--        keeps the raw import separate from the modelled data.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_transactions;
CREATE TABLE stg_transactions (
    row_id                  INT,               -- the unnamed index column in the CSV
    trans_date_trans_time   DATETIME,
    cc_num                  BIGINT,
    merchant                VARCHAR(120),      -- note: raw values are prefixed with "fraud_"
    category                VARCHAR(60),
    amt                     DECIMAL(10,2),
    first                   VARCHAR(60),
    last                    VARCHAR(60),
    gender                  CHAR(1),
    street                  VARCHAR(120),
    city                    VARCHAR(60),
    state                   VARCHAR(5),
    zip                     VARCHAR(10),
    lat                     DECIMAL(9,6),      -- customer home latitude
    `long`                  DECIMAL(9,6),      -- customer home longitude (backticked: LONG is reserved-ish)
    city_pop                INT,
    job                     VARCHAR(120),
    dob                     DATE,
    trans_num               VARCHAR(64),
    unix_time               BIGINT,
    merch_lat               DECIMAL(9,6),      -- merchant latitude AT transaction time (varies per txn)
    merch_long              DECIMAL(9,6),      -- merchant longitude at transaction time
    is_fraud                TINYINT(1)
);


-- ---------------------------------------------------------------------
-- STEP 3 : NORMALIZED TABLES
-- ---------------------------------------------------------------------

-- 3a. CUSTOMERS
-- WHY : One row per credit-card holder. In this dataset cc_num is unique
--       per customer, so it is a natural PRIMARY KEY.
DROP TABLE IF EXISTS Customers;
CREATE TABLE Customers (
    cc_num      BIGINT       PRIMARY KEY,
    first       VARCHAR(60),
    last        VARCHAR(60),
    gender      CHAR(1),
    street      VARCHAR(120),
    city        VARCHAR(60),
    state       VARCHAR(5),
    zip         VARCHAR(10),
    lat         DECIMAL(9,6),
    `long`      DECIMAL(9,6),
    city_pop    INT,
    job         VARCHAR(120),
    dob         DATE
);

-- 3b. MERCHANTS
-- WHY : The raw file has no merchant ID, only a repeated merchant NAME.
--       We create a surrogate AUTO_INCREMENT key (merchant_id) as the
--       PRIMARY KEY. Each merchant maps to exactly one category, so
--       category lives here. (merch_lat/merch_long stay in Transactions
--       because they change per transaction - they are GPS-at-purchase.)
DROP TABLE IF EXISTS Merchants;
CREATE TABLE Merchants (
    merchant_id     INT AUTO_INCREMENT PRIMARY KEY,
    merchant_name   VARCHAR(120),
    category        VARCHAR(60),
    UNIQUE KEY uq_merchant_name (merchant_name)  -- prevents duplicate merchants
);

-- 3c. TRANSACTIONS
-- WHY : The fact table - one row per transaction. trans_num is already
--       unique in the dataset, so it is the PRIMARY KEY. Two FOREIGN KEYS
--       link each transaction to its customer and its merchant.
DROP TABLE IF EXISTS Transactions;
CREATE TABLE Transactions (
    trans_num               VARCHAR(64) PRIMARY KEY,
    cc_num                  BIGINT,
    merchant_id             INT,
    trans_date_trans_time   DATETIME,
    unix_time               BIGINT,
    amt                     DECIMAL(10,2),
    merch_lat               DECIMAL(9,6),
    merch_long              DECIMAL(9,6),
    is_fraud                TINYINT(1),
    CONSTRAINT fk_txn_customer
        FOREIGN KEY (cc_num)       REFERENCES Customers(cc_num),
    CONSTRAINT fk_txn_merchant
        FOREIGN KEY (merchant_id)  REFERENCES Merchants(merchant_id)
);

-- ---------------------------------------------------------------------
-- Schema is ready. Next: run 02_load_data.sql to import the CSV and
-- populate these three tables from the staging table.
-- ---------------------------------------------------------------------
