-- Athena setup for the AWS Job Market Tracker.
-- Run each statement separately in the Athena query editor (Ohio / us-east-2).
-- If your bucket name is different, replace jobtracker-jordanlai-data below.


-- 1. Create a database (a folder for your tables).
CREATE DATABASE IF NOT EXISTS jobtracker;


-- 2. Create a table over the processed JSON Lines files.
--    Partition projection tells Athena that every dt=YYYY-MM-DD folder is a
--    partition, so new days show up automatically. No crawler or
--    "MSCK REPAIR TABLE" is needed.
CREATE EXTERNAL TABLE IF NOT EXISTS jobtracker.postings (
  id                  string,
  search_term         string,
  title               string,
  company             string,
  location            string,
  state               string,
  category            string,
  contract_type       string,
  contract_time       string,
  created             string,
  salary_min          double,
  salary_max          double,
  salary_is_predicted boolean,
  skills              array<string>,
  fetched_on          string
)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://jobtracker-jordanlai-data/processed/postings/'
TBLPROPERTIES (
  'projection.enabled'        = 'true',
  'projection.dt.type'        = 'date',
  'projection.dt.format'      = 'yyyy-MM-dd',
  'projection.dt.range'       = '2026-10-01,NOW',
  'projection.dt.interval'    = '1',
  'projection.dt.interval.unit' = 'DAYS',
  'storage.location.template' = 's3://jobtracker-jordanlai-data/processed/postings/dt=${dt}/'
);


-- 3. Create a view with each posting counted once.
--    The same posting is often returned on several days in a row (the fetch
--    asks for postings up to 7 days old), so this keeps only its first
--    appearance.
CREATE OR REPLACE VIEW jobtracker.postings_unique AS
SELECT *
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY search_term, id ORDER BY dt) AS rn
  FROM jobtracker.postings
)
WHERE rn = 1;