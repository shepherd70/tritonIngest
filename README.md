# tritonIngest

<!-- badges: start -->
[![R-CMD-check](https://github.com/shepherd70/tritonIngest/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/shepherd70/tritonIngest/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/shepherd70/tritonIngest)](https://github.com/shepherd70/tritonIngest/releases)
<!-- badges: end -->

Domain-agnostic R primitives for ingesting messy field and laboratory data
workbooks. Shared plumbing for the `water-chemistry-qaqc` (chemistry) and
`bw-analysis-code` (fish / effort / habitat) projects so they don't duplicate
their ingestion layers.

**It contains no domain knowledge, statistics, or plotting** — just the reusable
ingestion engine. See [`DESIGN.md`](DESIGN.md) for the rationale, full API, and
the cross-repo migration plan.

## What it does

- **Read** CSV/TSV/XLSX as all-text (`read_tabular`) so fragile notation
  survives; coerce mixed Excel-serial/ISO dates (`coerce_excel_date`).
- **Clean** structural junk — find the real header row and strip blank rows /
  spacer columns when a workbook has title or metadata rows above the data
  (`clean_table`, `find_header_row`, `drop_blank_rows`, `drop_blank_cols`).
- **Reshape** — detect long vs wide layout (`detect_layout`) and melt wide →
  long (`melt_wide`).
- **Map to a schema** — declare a contract (`cf_field` + `as_contract`),
  auto-map source columns onto it by exact / synonym / fuzzy match (`auto_map`),
  apply + coerce (`apply_column_map`), validate (`validate_against_contract`),
  and fill/complete (`complete_to_contract`, `contract_is_ready`).
- **Reuse mappings** — save/load named JSON column-mapping profiles
  (`save_mapping_profile`, `load_mapping_profile`, …).
- **Lab values** — parse non-detects (`parse_censored`), substitute
  (`apply_substitution`, `working_values`), reconcile units (`convert_units`).
- **Validate (generic)** — run a battery of domain-agnostic schema checks that
  each return failure messages, then abort once with the collected set
  (`check_required_columns`, `check_column_types`, `check_no_na`,
  `validation_abort`). Domain rules stay in the consuming packages.
- **Cache** — materialise the parsed canonical object to a fast-reload cache
  keyed by a fingerprint of the source file, so an unchanged source skips
  re-ingestion and a moved source auto-invalidates (`write_cache`, `read_cache`,
  `cached_ingest`; `rds` or `parquet` backend).
- **Exchange verified artifacts** — write/read canonical Parquet or Feather
  bundles with source identity, transformation identity, checksums, and shared
  JSON diagnostics (`write_canonical_bundle`, `read_canonical_bundle`).

Cross-language records are governed by the separately released
`tabular-ingestion-spec` repository (pinned to `1.0.0-rc.1`). The Python
spreadsheet-cleanup service may preserve and inventory environmental inputs,
but this R package remains the authoritative environmental canonicalizer; the
two engines do not call each other at runtime.

## Install

```r
remotes::install_github("shepherd70/tritonIngest")
```

## Typical flow

```r
library(tritonIngest)

# read header-less so title/metadata rows above the header can be stripped
raw   <- read_tabular("workbook.xlsx", sheet = "Data", col_names = FALSE)
tidy  <- clean_table(raw)                         # find header, drop blank rows/cols
long  <- if (detect_layout(tidy)$layout == "wide")
           melt_wide(tidy, param_cols = c("Zinc", "Copper")) else tidy

# declare what the analysis needs (each project keeps its own contracts)
chem <- as_contract(list(
  cf_field("site",      "character", required = TRUE,  synonyms = "station"),
  cf_field("parameter", "character", required = TRUE,  synonyms = "analyte"),
  cf_field("value_raw", "character", required = TRUE)
))

mapping <- auto_map(names(long), chem)            # best-guess column -> field
mapped  <- apply_column_map(long, mapping, chem)  # rename + coerce
report  <- validate_against_contract(mapped, chem)
parsed  <- parse_censored(mapped$value_raw)       # non-detects -> value/censored/DL
```

## Status

v0.7.0 release candidate — fail-closed headers/coercion, strict typed
contracts, transformation-aware cache v2, fingerprinted profile v2, structured
diagnostics, and verified canonical bundles. Both R consumers are being tested
against this candidate: fish/effort/habitat keeps its domain contracts, while
water chemistry keeps its strict local profile and carries left/right censor
metadata into its domain object.
