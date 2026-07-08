# Package index

## Read & dates

Read tabular sources as all-text so fragile notation survives; verify
the file’s type from its bytes; coerce mixed date encodings.

- [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
  : Read a tabular data file (CSV/TSV/XLSX) as all-text columns.
- [`sniff_format()`](https://shepherd70.github.io/tritonIngest/reference/sniff_format.md)
  : Identify a file's real type from its leading bytes.
- [`coerce_excel_date()`](https://shepherd70.github.io/tritonIngest/reference/coerce_excel_date.md)
  : Coerce mixed Excel-serial / date-string values to Date.

## Worksheets

Enumerate a workbook’s sheets (including hidden ones) and read them all.

- [`list_sheets()`](https://shepherd70.github.io/tritonIngest/reference/list_sheets.md)
  : List the worksheets of a workbook, with their visibility.
- [`read_all_sheets()`](https://shepherd70.github.io/tritonIngest/reference/read_all_sheets.md)
  : Read every worksheet of a workbook.

## Clean structural junk

Recover the real header row and strip blank rows / spacer columns /
label rows from dirty workbooks.

- [`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md)
  : Clean a freshly-read table: promote the header and strip junk.

- [`find_header_row()`](https://shepherd70.github.io/tritonIngest/reference/find_header_row.md)
  : Find the most likely header row in a header-less table.

- [`drop_blank_rows()`](https://shepherd70.github.io/tritonIngest/reference/drop_blank_rows.md)
  : Drop fully-blank rows from a data frame.

- [`drop_blank_cols()`](https://shepherd70.github.io/tritonIngest/reference/drop_blank_cols.md)
  : Drop fully-blank columns from a data frame.

- [`drop_label_rows()`](https://shepherd70.github.io/tritonIngest/reference/drop_label_rows.md)
  :

  Drop label rows: rows carrying fewer than `min_cells` populated cells.

## Reshape layout

Detect long / wide / transposed layout and reshape to long.

- [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
  : Heuristically detect whether a table is long/tidy or wide.
- [`melt_wide()`](https://shepherd70.github.io/tritonIngest/reference/melt_wide.md)
  : Melt a wide table (variables as columns) to long form.
- [`looks_transposed()`](https://shepherd70.github.io/tritonIngest/reference/looks_transposed.md)
  : Does this table hold analytes down a column and samples across the
  header?
- [`transpose_table()`](https://shepherd70.github.io/tritonIngest/reference/transpose_table.md)
  : Transpose an analyte-by-sample results matrix into a tidy long
  table.

## Column contracts & mapping

Declare a schema, auto-map source columns onto it by exact / synonym /
fuzzy match, coerce, and complete.

- [`cf_field()`](https://shepherd70.github.io/tritonIngest/reference/cf_field.md)
  : Build one contract field specification.
- [`as_contract()`](https://shepherd70.github.io/tritonIngest/reference/as_contract.md)
  : Coerce field specs into a contract tibble.
- [`contract_fields()`](https://shepherd70.github.io/tritonIngest/reference/contract_fields.md)
  : Field names of a contract.
- [`auto_map()`](https://shepherd70.github.io/tritonIngest/reference/auto_map.md)
  : Auto-map source columns onto a contract.
- [`apply_column_map()`](https://shepherd70.github.io/tritonIngest/reference/apply_column_map.md)
  : Apply a column mapping to a source data frame.
- [`complete_to_contract()`](https://shepherd70.github.io/tritonIngest/reference/complete_to_contract.md)
  : Complete a mapped frame to the full contract schema.
- [`contract_is_ready()`](https://shepherd70.github.io/tritonIngest/reference/contract_is_ready.md)
  : Is a mapped frame ready to use for a contract?
- [`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md)
  : Check whether an actual R class satisfies an expected type spec
- [`is_value_like()`](https://shepherd70.github.io/tritonIngest/reference/is_value_like.md)
  : Does a character vector look numeric-ish (allowing censored
  notation)?

## Mapping profiles

Save, load, and manage named JSON column-mapping profiles for reuse
across runs.

- [`save_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/save_mapping_profile.md)
  : Save a mapping profile to disk.
- [`load_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/load_mapping_profile.md)
  : Load a mapping profile from disk.
- [`list_mapping_profiles()`](https://shepherd70.github.io/tritonIngest/reference/list_mapping_profiles.md)
  : List saved mapping profiles.
- [`delete_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/delete_mapping_profile.md)
  : Delete a mapping profile.
- [`mapping_profiles_dir()`](https://shepherd70.github.io/tritonIngest/reference/mapping_profiles_dir.md)
  : Resolve (and optionally create) the mapping-profiles directory.

## Lab values

Parse non-detects, substitute working values, and reconcile units.

- [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
  : Parse raw result text into value / censoring / limit / qualifier.
- [`apply_substitution()`](https://shepherd70.github.io/tritonIngest/reference/apply_substitution.md)
  : Apply a simple substitution rule to censored values.
- [`working_values()`](https://shepherd70.github.io/tritonIngest/reference/working_values.md)
  : Working numeric values for a censoring method.
- [`convert_units()`](https://shepherd70.github.io/tritonIngest/reference/convert_units.md)
  : Convert mass-concentration or mass-fraction values between common
  units.

## Validation (generic)

Domain-agnostic schema checks that each return failures, then abort once
with the collected set.

- [`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md)
  : Check that required columns are present in a data frame
- [`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md)
  : Check that columns have expected types
- [`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md)
  : Check that key columns contain no NA values
- [`check_unique()`](https://shepherd70.github.io/tritonIngest/reference/check_unique.md)
  : Check that a set of columns forms a unique key
- [`check_range()`](https://shepherd70.github.io/tritonIngest/reference/check_range.md)
  : Check that numeric columns fall inside declared bounds
- [`check_monotonic()`](https://shepherd70.github.io/tritonIngest/reference/check_monotonic.md)
  : Check that a date/numeric column runs monotonically
- [`validate_against_contract()`](https://shepherd70.github.io/tritonIngest/reference/validate_against_contract.md)
  : Validate a (mapped) data frame against a contract.
- [`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
  : Abort with a classed error listing all collected validation failures

## Cache

Materialise the canonical object to a fingerprinted fast-reload cache.

- [`write_cache()`](https://shepherd70.github.io/tritonIngest/reference/write_cache.md)
  : Write a parsed object to the materialisation cache.
- [`read_cache()`](https://shepherd70.github.io/tritonIngest/reference/read_cache.md)
  : Read from the materialisation cache, if present and still fresh.
- [`cached_ingest()`](https://shepherd70.github.io/tritonIngest/reference/cached_ingest.md)
  : Ingest a source, using the cache when fresh and rebuilding it when
  not.
- [`cache_dir()`](https://shepherd70.github.io/tritonIngest/reference/cache_dir.md)
  : Resolve (and optionally create) the cache directory.
