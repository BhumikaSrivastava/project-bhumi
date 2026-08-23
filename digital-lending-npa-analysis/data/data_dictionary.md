# Data Dictionary — Loan Book

| Column | Description |
|---|---|
| loan_id | Unique loan account identifier |
| disbursed_amount | Actual amount disbursed to the borrower (₹) |
| asset_cost | Cost of the vehicle/asset financed (₹) |
| ltv | Loan-to-value ratio (%) |
| branch_id | Branch that originated the loan |
| state_id | State of disbursement — anonymised in the source data, no name mapping is published |
| employment_type | Salaried / Self employed / Not Captured |
| disbursal_date | Date the loan was disbursed |
| bureau_score | CIBIL/bureau credit score (0 = no bureau history) |
| bureau_score_desc | Bureau's own risk-band label for the score |
| pri_overdue_accts / sec_overdue_accts | Count of overdue accounts on the borrower's primary/secondary bureau records |
| total_overdue_accts | pri + sec overdue accounts combined |
| delinquent_accts_6m | Accounts gone delinquent in the last 6 months |
| bureau_inquiries | Number of credit inquiries on the borrower's bureau file |
| loan_default | 1 = loan defaulted, 0 = current (target variable) |
| dpd_bucket | Derived DPD-severity bucket (proxy — see README for why) |
