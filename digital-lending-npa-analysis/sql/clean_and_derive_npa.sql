-- ============================================================================
-- Loan Book Cleaning & NPA Analysis
-- Project: Digital Lending - Loan Book & NPA Risk Analysis (L&T Vehicle Loans data)
-- Author: Bhumika Srivastava
-- ============================================================================
-- Notes:
-- - raw file is loan_book_raw.csv, loaded into stg_loan_raw as-is
-- - Employment.Type has both NULLs and blank strings, need to standardise both
-- - found 25 exact duplicate UniqueIDs while checking row counts - dropping those
-- - PERFORM_CNS.SCORE = 0 isn't a real score, it means "no bureau history" per
--   the score description column, so excluding those from average-score calcs
-- - dataset does not include a running DPD/repayment-history table (would need
--   a separate monthly-balance file for that), so I'm using loan_default = 1 as
--   the NPA population and PRI/SEC overdue-account counts as a DPD-severity
--   proxy - flagging this clearly in the summary sheet so it's not confused
--   with actual RBI IRAC-classified DPD data
-- ============================================================================

DROP TABLE IF EXISTS loan_clean;
DROP TABLE IF EXISTS npa_summary_state;
DROP TABLE IF EXISTS npa_summary_score_band;
DROP TABLE IF EXISTS npa_summary_employment;
DROP TABLE IF EXISTS dpd_bucket_summary;

-- ----------------------------------------------------------------------------
-- STEP 1: Clean + de-dupe + standardise
-- ----------------------------------------------------------------------------
CREATE TABLE loan_clean AS
WITH dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY "UniqueID" ORDER BY "UniqueID") AS rn
    FROM stg_loan_raw
),
base AS (
    SELECT
        "UniqueID"                                  AS loan_id,
        CAST(disbursed_amount AS REAL)               AS disbursed_amount,
        CAST(asset_cost AS REAL)                     AS asset_cost,
        CAST(ltv AS REAL)                            AS ltv,
        branch_id,
        State_ID                                     AS state_id,
        -- blanks and NULLs both mean "not captured" - fold into one label
        CASE
            WHEN "Employment.Type" IS NULL OR TRIM("Employment.Type") = ''
                THEN 'Not Captured'
            ELSE TRIM("Employment.Type")
        END                                          AS employment_type,
        DisbursalDate                                AS disbursal_date,
        CAST("PERFORM_CNS.SCORE" AS INTEGER)          AS bureau_score,
        "PERFORM_CNS.SCORE.DESCRIPTION"               AS bureau_score_desc,
        CAST("PRI.OVERDUE.ACCTS" AS INTEGER)          AS pri_overdue_accts,
        CAST("SEC.OVERDUE.ACCTS" AS INTEGER)          AS sec_overdue_accts,
        CAST("PRI.OVERDUE.ACCTS" AS INTEGER) + CAST("SEC.OVERDUE.ACCTS" AS INTEGER) AS total_overdue_accts,
        CAST("DELINQUENT.ACCTS.IN.LAST.SIX.MONTHS" AS INTEGER) AS delinquent_accts_6m,
        CAST("NO.OF_INQUIRIES" AS INTEGER)            AS bureau_inquiries,
        loan_default
    FROM dedup
    WHERE rn = 1
)
SELECT
    b.*,
    sl.State_Name AS state_name,
    -- DPD-severity bucket, derived from overdue-account count as a proxy
    -- (see note at top of script re: no raw DPD/repayment-history table)
    CASE
        WHEN b.loan_default = 0 THEN '0 - Current'
        WHEN b.total_overdue_accts = 0 THEN '1-30 DPD (proxy)'
        WHEN b.total_overdue_accts = 1 THEN '31-60 DPD (proxy)'
        WHEN b.total_overdue_accts = 2 THEN '61-90 DPD (proxy)'
        ELSE '90+ DPD / NPA (proxy)'
    END AS dpd_bucket
FROM base b
LEFT JOIN state_lookup sl ON b.state_id = sl.State_ID;


-- ----------------------------------------------------------------------------
-- STEP 2: Portfolio-level NPA summary by state
-- (GNPA% here = count-based NPA rate; swap in disbursed_amount sums for a
--  value-weighted GNPA% if that's what the business wants to see instead)
-- ----------------------------------------------------------------------------
CREATE TABLE npa_summary_state AS
SELECT
    state_name,
    COUNT(*)                                                   AS total_loans,
    SUM(disbursed_amount)                                      AS total_disbursed,
    SUM(loan_default)                                          AS npa_count,
    ROUND(100.0 * SUM(loan_default) / COUNT(*), 2)             AS gnpa_pct,
    ROUND(100.0 * SUM(CASE WHEN dpd_bucket LIKE '61-90%' OR dpd_bucket LIKE '90+%'
                            THEN 1 ELSE 0 END) / COUNT(*), 2)   AS par_60_pct
FROM loan_clean
GROUP BY state_name
ORDER BY gnpa_pct DESC;


-- ----------------------------------------------------------------------------
-- STEP 3: NPA by bureau score band - sanity check that risk scoring works
-- ----------------------------------------------------------------------------
CREATE TABLE npa_summary_score_band AS
SELECT
    CASE
        WHEN bureau_score = 0 THEN 'No Bureau History'
        WHEN bureau_score >= 750 THEN 'A: 750+ (Very Low Risk)'
        WHEN bureau_score >= 700 THEN 'B: 700-749 (Low Risk)'
        WHEN bureau_score >= 650 THEN 'C: 650-699 (Medium Risk)'
        WHEN bureau_score >= 600 THEN 'D: 600-649 (High Risk)'
        ELSE 'E: <600 (Very High Risk)'
    END AS score_band,
    COUNT(*)                                        AS total_loans,
    SUM(loan_default)                                AS npa_count,
    ROUND(100.0 * SUM(loan_default) / COUNT(*), 2)   AS gnpa_pct
FROM loan_clean
GROUP BY score_band
ORDER BY gnpa_pct DESC;


-- ----------------------------------------------------------------------------
-- STEP 4: NPA by employment type
-- ----------------------------------------------------------------------------
CREATE TABLE npa_summary_employment AS
SELECT
    employment_type,
    COUNT(*)                                        AS total_loans,
    SUM(loan_default)                                AS npa_count,
    ROUND(100.0 * SUM(loan_default) / COUNT(*), 2)   AS gnpa_pct
FROM loan_clean
GROUP BY employment_type
ORDER BY gnpa_pct DESC;


-- ----------------------------------------------------------------------------
-- STEP 5: DPD bucket distribution (portfolio-at-risk view)
-- ----------------------------------------------------------------------------
CREATE TABLE dpd_bucket_summary AS
SELECT
    dpd_bucket,
    COUNT(*)                                                        AS loan_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM loan_clean), 2)  AS pct_of_book,
    SUM(disbursed_amount)                                           AS disbursed_amount_at_risk
FROM loan_clean
GROUP BY dpd_bucket
ORDER BY
    CASE dpd_bucket
        WHEN '0 - Current' THEN 1
        WHEN '1-30 DPD (proxy)' THEN 2
        WHEN '31-60 DPD (proxy)' THEN 3
        WHEN '61-90 DPD (proxy)' THEN 4
        ELSE 5
    END;
