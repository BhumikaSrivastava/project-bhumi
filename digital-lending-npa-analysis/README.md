# Digital Lending — Loan Book & NPA Risk Analysis

## Business context
Digital lenders and NBFCs in India live and die by how early they can spot risk concentration
in their loan book. Post the RBI's 2022 Digital Lending Guidelines, NPA/PAR monitoring by
segment (state, credit-score band, employment type) is standard practice for any lending risk
or business-analyst team. This project recreates that workflow on a real vehicle-loan dataset.

## Data source
[L&T Vehicle Loan Default Prediction](https://www.kaggle.com/datasets/mamtadhaker/lt-vehicle-loan-default-prediction)
— loan-level data released by L&T Financial Services, ~233k rows, 42 columns (disbursement
details, KYC flags, and CIBIL/bureau credit history per loan). `data/sample_loan_data.csv`
here has a few hundred rows for reference — grab the full file from the Kaggle link above to
reproduce this end to end.

## Tools
SQL (SQLite) for cleaning, de-duplication, and NPA/DPD-bucket derivation → Excel for
formula-driven KPI and segment reporting (SUMIFS/COUNTIFS/INDEX-MATCH, no hardcoded numbers)
→ Power BI for the dashboard.

## What I did
- Cleaned the raw loan book in SQL: dropped duplicate loan IDs, standardized blank/null
  `Employment.Type` values, joined a branch/state lookup table
- Derived a DPD-bucket proxy since the dataset doesn't include a month-by-month repayment
  history — defaulted loans are bucketed by their overdue bureau-account count as a severity
  proxy (flagged clearly wherever it's used — this is *not* RBI IRAC-classified DPD)
- Built GNPA% and PAR60%+ summaries by state, credit-score band, and employment type in Excel,
  all formula-driven off the cleaned data sheet
- [Power BI dashboard — in progress / link once published]

## Key findings
- Overall book GNPA: **25.0%**, PAR90 (NPA) at 0.25%
- **West Bengal** is the highest-risk state (29.4% GNPA) vs. **Himachal Pradesh** the lowest (22.0%)
- Credit-score bands show a clean risk gradient — 7.8% GNPA for 750+ scores vs. 20.1% for sub-600,
  a good sanity check that the bureau score is actually predictive on this book
- Self-employed borrowers default at 27.2% vs. 22.4% for salaried

## Limitations
- No monthly repayment/DPD-history table in the source data, so DPD buckets beyond "Current"
  are derived, not observed — see the SQL comments for exact logic
- GNPA% here is count-based (share of loans), not value-weighted (share of disbursed ₹) —
  worth adding as a second cut if extending this

## Folder contents
- `sql/clean_and_derive_npa.sql` — cleaning + NPA-bucket derivation
- `data/sample_loan_data.csv`, `data/data_dictionary.md`
- `excel/Loan_Book_NPA_Analysis.xlsx`
