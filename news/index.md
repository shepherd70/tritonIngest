# Changelog

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
