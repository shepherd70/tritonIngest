# Changelog

## tritonIngest 0.7.1

Real-workbook hardening following a 13-sheet marine water-quality
workbook test.

- [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  and
  [`is_value_like()`](https://shepherd70.github.io/tritonIngest/reference/is_value_like.md)
  normalize the Unicode mathematical operators U+2264/U+2265 to ASCII
  `<`/`>` using runtime code-point construction. Successful parses
  retain a `parse_note` recording that normalization.
- New
  [`inspect_workbook()`](https://shepherd70.github.io/tritonIngest/reference/inspect_workbook.md)
  inventories formula cells, formulas without cached results, merged
  ranges, visibility, and sheet identity directly from OOXML.
- [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
  and
  [`read_all_sheets()`](https://shepherd70.github.io/tritonIngest/reference/read_all_sheets.md)
  gain `formula_policy = "warn"`, `"error"`, or `"allow"`. Formula reads
  attach shared `formula_present` and `formula_gap` diagnostics because
  readxl consumes Excel’s cached results.
- [`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md)
  preserves ingestion diagnostics, and
  `write_canonical_bundle(diagnostics = NULL)` inherits them by default.
- Headerless XLSX reads use minimal name repair, eliminating repetitive
  readxl/tibble `New names` output while preserving positional source
  columns.
- A secure, opt-in real-workbook harness now verifies source and
  workbook identity, exact R cell digests, independent openpyxl semantic
  cell digests, censor and reshape conservation, and canonical-bundle
  round-trip without committing private workbook values.

## tritonIngest 0.7.0

- Cache manifests are now backend-specific `triton-cache/v2` records
  with source, transformation, backend, and artifact-checksum
  verification, atomic writes, and bounded lock-directory concurrency.
  Legacy v1 entries are misses.
- Added verified Parquet/Feather canonical bundles using
  `tabular-artifact/v1` manifests and `tabular-diagnostic/v1`
  diagnostics.
- Duplicate headers and lossy contract coercion now fail closed by
  default. Explicit overrides retain structured review diagnostics.
- Contracts share one strict type registry (including date, datetime,
  and time), expose stable fingerprints, and report
  total/populated/missing/invalid counts.
- Mapping profiles use `triton-mapping-profile/v2` and bind to contract
  plus ordered-header fingerprints. V1 profiles require explicit
  upgrade.
- Bare right-censor tokens accept a separate `censor_limit`; unit
  normalization folds both Unicode micro characters to ASCII `u` without
  source-code literals.

## tritonIngest 0.6.0

Pressure-test follow-up (2026-07): fixes the nine root causes recorded
in `audits/tritonIngest-pressure-test-2026-07-08.md`. Four of them
corrupted data **silently** – they returned a plausible wrong answer
with no error, warning or `NA` – and are now loud.

### Silent corruptions, now loud

- **[`coerce_excel_date()`](https://shepherd70.github.io/tritonIngest/reference/coerce_excel_date.md)
  no longer prefix-matches a date format.** Base
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html) ignores unconsumed
  trailing characters, so `"18-08-2024"` matched the default
  `"%Y-%m-%d"` as year 18, month 08, day 20 and returned `0018-08-20` –
  a valid `Date`, no warning. An element must now match a format over
  its **whole length** before the parse is accepted, so day-first
  strings fall through to the existing “unparsed” warning. Pass
  `strict = FALSE` for the old behaviour.
  [`coerce_excel_date()`](https://shepherd70.github.io/tritonIngest/reference/coerce_excel_date.md)
  also trims the whitespace and newlines Excel leaves in wrapped cells,
  and warns when a value in 1500-2500 is treated as an Excel serial (the
  bare-year hazard: `"2024"` -\> `1905-07-16`).

- **[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
  verifies the file’s signature against its extension.** An `.xlsx`
  workbook served under a `.csv` name used to be handed to readr, which
  read the ZIP’s first member and returned a one-column tibble whose
  name was an XML declaration – no error. It is now an error naming the
  real type. New
  [`sniff_format()`](https://shepherd70.github.io/tritonIngest/reference/sniff_format.md)
  exposes the check; new `format=` overrides the extension.

- **[`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  understands right-censored results.** `">2420"`, `"> 80"` and the
  `TNTC` token were `"unparseable result text"`, i.e. erased – and they
  are exactly the permit exceedances. They are now `censored = TRUE`
  with the new `censor_direction` column (`"none"`/`"left"`/`"right"`),
  and their bound in the new `censor_limit` column.

  `detection_limit` stays `NA` for a right-censored row, on purpose: a
  `">2420"` result has no detection limit, it has a quantitation
  ceiling. That split is what keeps the **default safe** for a caller
  that has not yet learned about right-censoring.
  `apply_substitution(value, censored, detection_limit)` returns `NA`
  for those rows – exactly as in 0.5.0 – rather than
  `fraction * ceiling`, which would fabricate a number *below* the true
  value. A supplied DL column is likewise never promoted to a ceiling.

- **[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
  and
  [`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md)
  warn about duplicate source column names** before repairing them.
  readr’s rename was a *message*, which
  [`suppressMessages()`](https://rdrr.io/r/base/message.html) erased; a
  duplicated analyte label is the signature of a mislabelled or
  copy-pasted column.

### Breaking changes

- `auto_map(max_distance = )` now defaults to **`0`** (exact and synonym
  matching only). Edit distance over systematically-related analyte
  names is unsafe: `"LEPH_C10_C19"` is distance 1 from `"EPH_C10_C19"`
  but distance 9 from the correct `"LEPH_C10_C19_less_PAH"`, and a
  `"dl"` synonym is distance 2 from a `"pH"` column. Pass
  `max_distance = 2L` to restore the old behaviour; every fuzzy match is
  then reported with a warning.
  [`auto_map()`](https://shepherd70.github.io/tritonIngest/reference/auto_map.md)
  also warns when a contract field binds to an exactly-named column
  while a synonym matches a different one.
- [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  returns three new columns, `censor_direction`, `censor_limit` and
  `qualifier`. Existing columns keep their semantics, except that
  right-censored values are now `censored = TRUE` rather than
  `censored = NA`. Code that does `sum(x$censored, na.rm = TRUE)` will
  therefore count over-range results as censored, which they are. Code
  that binds the result by position rather than by name must be updated.
- [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  treats `"-"`, `"--"`, `"n/a"` and `"N/A"` as **missing**
  (`na_strings=`) rather than unparseable, and separates laboratory
  qualifier flags from the number they decorate (`"178d"` -\> value 178,
  qualifier `"d"`; `qualifiers = FALSE` restores the strict reading).
  Narrative cells such as `"5.4 to 8.7"` and `"50% survival"` stay
  unparseable by design.
- [`is_value_like()`](https://shepherd70.github.io/tritonIngest/reference/is_value_like.md),
  [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
  and
  [`melt_wide()`](https://shepherd70.github.io/tritonIngest/reference/melt_wide.md)
  gain `na_strings=` and treat those placeholders as missing. Previously
  a wide sheet whose blanks were written as `"-"` lost most of its
  analyte columns to the 0.8 value-like threshold, and
  [`melt_wide()`](https://shepherd70.github.io/tritonIngest/reference/melt_wide.md)
  carried the `"-"` cells through as data.
- `ND_LT_REGEX` is now digit-strict. `"<-"`, `"<."`, `"<e"` and `"<+-"`
  used to match, yielding `censored = TRUE` with an `NA` limit and a
  clean `parse_note`.
- [`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md)
  gains `header_rows=`, `drop_labels=` and `sep=`; the positional
  signature `clean_table(df, header_row, trim_ws)` is unchanged.
- [`apply_substitution()`](https://shepherd70.github.io/tritonIngest/reference/apply_substitution.md)
  and
  [`working_values()`](https://shepherd70.github.io/tritonIngest/reference/working_values.md)
  gain `censor_direction=` and `censor_limit=`. Right-censored entries
  substitute to the ceiling itself, not to a fraction of it. Omitting
  both arguments reproduces the old all-left-censored behaviour *safely*
  (right-censored rows become `NA`, as they did in 0.5.0); naming a
  `"right"` entry in `censor_direction` without supplying `censor_limit`
  is an error rather than a guess.
  [`working_values()`](https://shepherd70.github.io/tritonIngest/reference/working_values.md)
  now also accepts the whole
  [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  tibble as its first argument – `working_values(parse_censored(x))` is
  the one-liner that handles both directions correctly.

### New

- [`list_sheets()`](https://shepherd70.github.io/tritonIngest/reference/list_sheets.md)
  returns every worksheet with its **visibility**
  (`"visible"`/`"hidden"`/`"veryHidden"`), which
  [`readxl::excel_sheets()`](https://readxl.tidyverse.org/reference/excel_sheets.html)
  does not report; a `veryHidden` sheet in position 1 is what
  [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
  reads by default.
  [`read_all_sheets()`](https://shepherd70.github.io/tritonIngest/reference/read_all_sheets.md)
  reads a whole workbook, optionally skipping hidden sheets. Previously
  nothing in the package could enumerate sheets, so `read_tabular(path)`
  silently ingested sheet 1 and discarded the rest.
- [`check_unique()`](https://shepherd70.github.io/tritonIngest/reference/check_unique.md),
  [`check_range()`](https://shepherd70.github.io/tritonIngest/reference/check_range.md)
  and
  [`check_monotonic()`](https://shepherd70.github.io/tritonIngest/reference/check_monotonic.md)
  extend the validation kernel from column-level counts to records:
  duplicate keys, physically impossible values (a pH of 42.4), and a
  sampling series that steps backwards.
- [`drop_label_rows()`](https://shepherd70.github.io/tritonIngest/reference/drop_label_rows.md)
  removes single-cell section dividers and footnote banners.
  `clean_table(drop_labels = TRUE)` does it in one pass.
- [`looks_transposed()`](https://shepherd70.github.io/tritonIngest/reference/looks_transposed.md)
  and
  [`transpose_table()`](https://shepherd70.github.io/tritonIngest/reference/transpose_table.md)
  handle the analyte-by-sample results matrix – a third layout, whose
  columns are numeric and which
  [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
  therefore used to call `"wide"`.
  [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
  now reports `layout = "transposed"` for it.
- [`apply_column_map()`](https://shepherd70.github.io/tritonIngest/reference/apply_column_map.md)
  warns when type coercion discards non-missing values, naming the
  field, the count and example tokens. Coercing a `numeric` field runs
  [`as.numeric()`](https://rdrr.io/r/base/numeric.html), which destroys
  every non-detect that
  [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  exists to preserve; the contract path never called it.

## tritonIngest 0.5.0

Audit follow-up (2026-06): closes the open correctness findings recorded
in `audits/tritonIngest-audit-2026-06.md`.

- [`convert_units()`](https://shepherd70.github.io/tritonIngest/reference/convert_units.md)
  gains the **mass/mass** ladder (`g/kg`, `mg/kg`, `ug/kg`, `ng/kg`,
  `mg/g`, `ug/g`, `ng/g`) alongside the existing mass/volume ladder, for
  tissue/sediment data. Conversions stay within a ladder (mass/volume
  and mass/mass are not interconvertible without a density). The Greek
  small mu (U+03BC) now folds onto the micro sign (U+00B5), so an
  instrument export’s `"μg/L"` matches `"µg/L"`. A non-identity
  conversion that cannot be resolved now returns `NA` **with a warning**
  rather than a silent `NA`, so an unsupported unit class is
  distinguishable from a genuinely missing value.
- [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  and
  [`apply_substitution()`](https://shepherd70.github.io/tritonIngest/reference/apply_substitution.md)
  now **validate vector lengths** (`detection_limit` must be length 1 or
  match the data; `censored` must match `value`) and error on a mismatch
  instead of silently recycling/misaligning.
- [`coerce_excel_date()`](https://shepherd70.github.io/tritonIngest/reference/coerce_excel_date.md)
  gains `formats=` (defaulting to unambiguous year-first layouts, so
  `"2024/08/22"` now parses), `origin=` (for the Mac/1904 date system),
  and `serial_range=` (to stop bare year-like integers being misread as
  serials). Values matching neither a serial nor any format now return
  `NA` **with a warning**.
- [`melt_wide()`](https://shepherd70.github.io/tritonIngest/reference/melt_wide.md)
  now errors when a retained id column is named `parameter`,
  `value_raw`, or `units` rather than silently clobbering it.
- [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
  /
  [`is_value_like()`](https://shepherd70.github.io/tritonIngest/reference/is_value_like.md)
  now share the one non-detect vocabulary (`ND_TOKENS`) and `<DL` regex
  used by
  [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md),
  so the layout and parsing token lists can no longer drift (e.g. a
  `"NON-DETECT"` column is now value-like to both).
- [`save_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/save_mapping_profile.md)
  now errors when a *different* profile name sanitises to the same file
  slug (it previously overwrote the unrelated profile silently);
  [`write_cache()`](https://shepherd70.github.io/tritonIngest/reference/write_cache.md)
  warns on the analogous explicit-key cache-slug collision.

## tritonIngest 0.4.3

- [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
  now recognises plural parameter/value column names (`"results"`,
  `"values"`, `"analytes"`, `"parameters"`, …) and trims surrounding
  whitespace from column names before matching. Lab exports such as ALS
  reports label their value column `"Results"` and pad headers
  (`"Analyte "`), which previously missed the long-format vocabulary and
  – when two or more numeric columns were present (result + detection
  limit + a numeric QC-lot id) – misclassified the table as wide,
  discarding the analyte column. This removes the need for the interim
  water-chemistry-qaqc guard.
