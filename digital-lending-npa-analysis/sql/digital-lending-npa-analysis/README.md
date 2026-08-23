# Digital Lending — Loan Book & NPA Risk Analysis

## Why I picked this
NBFCs and digital lenders in India have been under a lot more scrutiny since RBI's
2022 Digital Lending Guidelines, and NPA monitoring is basically the bread and
butter of any risk/BA team at a lender. I wanted a project that actually looked
like that kind of work instead of another generic sales dashboard, so I picked a
real vehicle-loan dataset from L&T Financial Services and tried to build the kind
of NPA/risk reporting an analyst there would actually be asked for.

## Data
[L&T Vehicle Loan Default Prediction](https://www.kaggle.com/datasets/mamtadhaker/lt-vehicle-loan-default-prediction)
on Kaggle — real loan-level data L&T released for an Analytics Vidhya hackathon a
few years back. 233,154 loans, 41 columns covering disbursement info, KYC flags,
and CIBIL/bureau history per loan. I've kept a small sample (`data/sample_loan_data.csv`,
~300 rows) in this repo just so you can see the shape of it — grab the full file
from Kaggle if you want to actually run the scripts yourself.

## What I did
Cleaned it up in SQL first — checked for duplicate loan IDs (there weren't any in
this particular file, though I kept the de-dup logic in since I'd normally expect
some), and standardized the ~7,700 rows where Employment Type was blank. Then
derived NPA/DPD-style risk buckets, which took a bit of thinking because the
dataset doesn't actually give you a month-by-month repayment history — no real
DPD tracking, just a single loan_default flag. So I used that flag as my NPA
population and used the borrower's overdue-bureau-account count as a rough proxy
for how "bad" the default is. It's not the same as real RBI IRAC-classified DPD
and I've said so pretty clearly in the workbook, but it's a reasonable stand-in
given what the data actually has.

From there I built out GNPA%/PAR60%+ summaries by state, credit score band, and
employment type in Excel — all live SUMIFS/COUNTIFS formulas off the cleaned
sheet, nothing hardcoded, so if you swap the data the numbers update themselves.
Power BI dashboard is next on my list (will link it here once it's done).

## What I found
- Book-wide GNPA comes out to **21.7%**, which actually lines up with the known
  default rate people quote for this dataset elsewhere, so that was a decent
  sanity check that I'd done the cleaning right
- There's a real spread by state — worth noting the dataset only gives you an
  anonymized `State_ID`, not actual state names, so I couldn't do a proper
  geography-based story here (a bit annoying, but better to be accurate than
  make up a mapping). Highest-risk State_ID sits at ~30.7% GNPA vs. ~11.8% for
  the lowest
- Credit score bands behave the way you'd hope — 14.7% GNPA for 750+ scores vs.
  26.1% for sub-600, so the bureau score is clearly doing real predictive work
  on this book
- Self-employed borrowers default a bit more than salaried ones (22.8% vs.
  20.4%) — not a huge gap, smaller than I expected honestly

## Where this falls short
- No repayment-history table means the DPD buckets past "Current" are a guess
  based on overdue accounts, not something I actually observed month to month
- GNPA% here is just a count of loans, not weighted by how much money is
  actually at risk — would be a good next step to redo this value-weighted
- State can't be tied to an actual region because the data anonymizes it

## In this folder
- `sql/clean_and_derive_npa.sql` — the cleaning + bucket-derivation script
- `data/sample_loan_data.csv`, `data/data_dictionary.md`
- `excel/Loan_Book_NPA_Analysis.xlsx`
