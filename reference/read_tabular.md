# Read a tabular data file (CSV/TSV/XLSX) as all-text columns.

Every column is read as character so notation like non-detect markers
(`"<0.01"`, `"ND"`) and codes with leading zeros are preserved for
downstream parsing. Pass `col_types` to override on a typed read when
that is not needed.

## Usage

``` r
read_tabular(
  path,
  sheet = NULL,
  col_types = NULL,
  col_names = TRUE,
  format = NULL
)
```

## Arguments

- path:

  File path. The extension selects the reader (csv/txt, tsv, xlsx/xls)
  unless `format` is given.

- sheet:

  Sheet name or index for Excel files (default: first sheet). Use
  [`list_sheets()`](https://shepherd70.github.io/tritonIngest/reference/list_sheets.md)
  to enumerate a workbook and
  [`read_all_sheets()`](https://shepherd70.github.io/tritonIngest/reference/read_all_sheets.md)
  to read them all – `read_tabular()` reads exactly one sheet.

- col_types:

  Optional column-type spec passed through to the underlying reader;
  default reads everything as text.

- col_names:

  Treat the first row as the header (`TRUE`, the default) or read every
  row as data with positional names (`FALSE`). Use `FALSE` when a
  workbook has title/metadata rows above the real header, then recover
  it with
  [`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md).

- format:

  Force a reader: one of `"csv"`, `"tsv"`, `"txt"`, `"xlsx"`, `"xls"`.
  Defaults to `NULL` (derive from the extension and verify against the
  file's signature).

## Value

A tibble.

## Details

The file's leading bytes are checked against its extension (see
[`sniff_format()`](https://shepherd70.github.io/tritonIngest/reference/sniff_format.md)):
an `.xlsx` workbook served under a `.csv` name is an error, not a silent
mis-parse. Pass `format=` to override the extension entirely.

Duplicate names in the source header are reported with a warning before
the underlying reader makes them unique.
