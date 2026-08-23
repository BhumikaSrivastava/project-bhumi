-- ============================================================================
-- Loan Book Cleaning & NPA Analysis
-- Digital Lending - Loan Book & NPA Risk Analysis (L&T Vehicle Loans data)
-- Bhumika Srivastava
-- ============================================================================
-- source file: loan_book_real.csv, from the Kaggle L&T Vehicle Loan Default
-- Prediction dataset (mamtadhaker) - 233,154 rows, loaded as-is into stg_loan_raw
--
-- things I ran into while cleaning this:
-- - Employment.Type has ~7,700 blank/NULL rows, standardising those to
--   'Not Captured' instead of dropping them, don't want to lose that many rows
-- - checked for duplicate UniqueIDs first thing, didn't find any in this file
--   but kept the ROW_NUMBER() de-dup step anyway, habit from the last project
--   where I did find dupes
-- - PERFORM_CNS.SCORE = 0 is NOT an actual score of zero, it means the bureau
--   has no history on that person (confirmed from the score description
--   column), so I'm keeping it as its own band instead of lumping it in with
--   genuinely bad scores
-- - wanted to do a state-wise map originally but State_ID here is anonymised -
--   Kaggle's data dictionary just says "State of disbursement", no name
--   mapping anywhere, so reporting by State_ID number instead of guessing
--   which number is which state
-- - biggest limitation: no month-by-month repayment/DPD table in this data,
--   so I can't build real DPD buckets the way an actual collections team
--   would. using loan_default=1 as my NPA population and bucketing severity
--   by overdue bureau-account count instead - it's a proxy, not real DPD,
--   calling that out wherever the bucket shows up so it doesn't get read as
--   RBI IRAC-classified data
-- ============================================================================

DROP TABLE IF EXISTS loan_clean;
DROP TABLE IF EXISTS npa_summary_state;
DROP TABLE IF EXISTS npa_summary_score_band;
DROP TABLE IF EXISTS npa_summary_employment;
DROP TABLE IF EXISTS dpd_bucket_summary;

-- ----------------------------------------------------------------------------
-- Step 1: clean it up + tag each loan with a DPD bucket
-- ----------------------------------------------------------------------------
CREATE TABLE loan_clean AS
WITH dedup AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY "UniqueID" ORDER BY "UniqueID") AS rn
    FROM stg_loan_raw
)
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
    loan_default,
    -- DPD-severity bucket, derived from overdue-account count as a proxy
    -- (see note at top of script re: no raw DPD/repayment-history table)
    CASE
        WHEN loan_default = 0 THEN '0 - Current'
        WHEN (CAST("PRI.OVERDUE.ACCTS" AS INTEGER) + CAST("SEC.OVERDUE.ACCTS" AS INTEGER)) = 0 THEN '1-30 DPD (proxy)'
        WHEN (CAST("PRI.OVERDUE.ACCTS" AS INTEGER) + CAST("SEC.OVERDUE.ACCTS" AS INTEGER)) = 1 THEN '31-60 DPD (proxy)'
        WHEN (CAST("PRI.OVERDUE.ACCTS" AS INTEGER) + CAST("SEC.OVERDUE.ACCTS" AS INTEGER)) = 2 THEN '61-90 DPD (proxy)'
        ELSE '90+ DPD / NPA (proxy)'
    END AS dpd_bucket
FROM dedup
WHERE rn = 1;


-- ----------------------------------------------------------------------------
-- STEP 2: NPA by State_ID (can't do actual state names, see note up top)
-- ----------------------------------------------------------------------------
CREATE TABLE npa_summary_state AS
SELECT
    state_id,
    COUNT(*)                                                   AS total_loans,
    SUM(disbursed_amount)                                      AS total_disbursed,
    SUM(loan_default)                                          AS npa_count,
    ROUND(100.0 * SUM(loan_default) / COUNT(*), 2)             AS gnpa_pct,
    ROUND(100.0 * SUM(CASE WHEN dpd_bucket LIKE '61-90%' OR dpd_bucket LIKE '90+%'
                            THEN 1 ELSE 0 END) / COUNT(*), 2)   AS par_60_pct
FROM loan_clean
GROUP BY state_id
ORDER BY gnpa_pct DESC;


-- ----------------------------------------------------------------------------
-- STEP 3: NPA by credit score band - wanted to check the bureau score is
-- actually doing something before I trusted it for anything else
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
-- STEP 4: NPA by employment type - salaried vs self-employed
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
-- STEP 5: how the book breaks down across DPD buckets (portfolio-at-risk)
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
