# tritonIngest 0.5.0

Audit follow-up (2026-06): closes the open correctness findings recorded in
`docs/tritonIngest-audit-2026-06.md`.

* `convert_units()` gains the **mass/mass** ladder (`g/kg`, `mg/kg`, `ug/kg`,
  `ng/kg`, `mg/g`, `ug/g`, `ng/g`) alongside the existing mass/volume ladder, for
  tissue/sediment data. Conversions stay within a ladder (mass/volume and
  mass/mass are not interconvertible without a density). The Greek small mu
  (U+03BC) now folds onto the micro sign (U+00B5), so an instrument export's
  `"μg/L"` matches `"µg/L"`. A non-identity conversion that cannot be resolved now
  returns `NA` **with a warning** rather than a silent `NA`, so an unsupported
  unit class is distinguishable from a genuinely missing value.
* `parse_censored()` and `apply_substitution()` now **validate vector lengths**
  (`detection_limit` must be length 1 or match the data; `censored` must match
  `value`) and error on a mismatch instead of silently recycling/misaligning.
* `coerce_excel_date()` gains `formats=` (defaulting to unambiguous year-first
  layouts, so `"2024/08/22"` now parses), `origin=` (for the Mac/1904 date
  system), and `serial_range=` (to stop bare year-like integers being misread as
  serials). Values matching neither a serial nor any format now return `NA`
  **with a warning**.
* `melt_wide()` now errors when a retained id column is named `parameter`,
  `value_raw`, or `units` rather than silently clobbering it.
* `detect_layout()` / `is_value_like()` now share the one non-detect vocabulary
  (`ND_TOKENS`) and `<DL` regex used by `parse_censored()`, so the layout and
  parsing token lists can no longer drift (e.g. a `"NON-DETECT"` column is now
  value-like to both).
* `save_mapping_profile()` now errors when a *different* profile name sanitises
  to the same file slug (it previously overwrote the unrelated profile silently);
  `write_cache()` warns on the analogous explicit-key cache-slug collision.

# tritonIngest 0.4.3

* `detect_layout()` now recognises plural parameter/value column names
  (`"results"`, `"values"`, `"analytes"`, `"parameters"`, ...) and trims
  surrounding whitespace from column names before matching. Lab exports such as
  ALS reports label their value column `"Results"` and pad headers (`"Analyte "`),
  which previously missed the long-format vocabulary and -- when two or more
  numeric columns were present (result + detection limit + a numeric QC-lot id)
  -- misclassified the table as wide, discarding the analyte column. This
  removes the need for the interim water-chemistry-qaqc guard.
