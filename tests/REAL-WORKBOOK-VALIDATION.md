# Secure real-workbook validation

The ordinary test suite uses only generated or sanitized fixtures. A private
workbook can be validated without copying it into this repository by setting
two environment variables and running the opt-in test:

```powershell
$env:TRITON_REAL_WORKBOOK = "C:\secure\source.xlsx"
$env:TRITON_REAL_WORKBOOK_PYTHON = "C:\path\to\python.exe"
Rscript -e "pkgload::load_all(); testthat::test_file('tests/testthat/test-real-workbook.R')"
```

The configured Python must provide `openpyxl`. If the Python variable is not
set, the independent-reader check is skipped; all R-only source, inventory,
transformation, and artifact checks still run.

## What is checked

The test fails on any unexpected change to:

- source SHA-256 or byte size;
- worksheet order, names, visibility, formula counts, missing cached formula
  results, or merged ranges;
- dimensions, nonblank counts, or exact all-text R cell digests for approved
  primary worksheets;
- cross-language semantic cell digests produced independently by readxl and
  openpyxl;
- censor-token counts, direction, parse success, or available censor limits;
- the representative wide-table layout and the conservation identity between
  nonblank measurement cells and emitted long records; or
- verified canonical-bundle round-trip, source identity, rows, and columns.

Exact R text digests deliberately preserve readxl's full-precision numeric text
and original line endings. Cross-language digests normalize line endings and
encode numeric values by their IEEE-754 bytes, so representation differences do
not hide a genuine cell change.

The baseline JSON contains hashes and structural counts only, never workbook
cell values. The independent Python helper prints the same privacy-safe record.

## Updating the baseline

Do not update `fixtures/real-workbook-baseline.json` merely to make a failed
test pass. A changed source hash establishes a new workbook version and requires
manual review of the source, the structural differences, and representative
cell-level differences. Record that approval before replacing the baseline.

The harness validates domain-agnostic ingestion. Chemistry-specific analytes,
sample keys, expected stations, units, detection-limit policy, and QA/QC rules
remain the responsibility of `water-chemistry-qaqc`.
