# Read a tabular data file (CSV/TSV/XLSX) as all-text columns.

Every column is read as character so notation like non-detect markers
(`"<0.01"`, `"ND"`) and codes with leading zeros are preserved for
downstream parsing. Pass `col_types` to override on a typed read when
that is not needed.

## Usage

``` r
read_tabular(path, sheet = NULL, col_types = NULL, col_names = TRUE)
```

## Arguments

- path:

  File path. The extension selects the reader (csv/txt, tsv, xlsx/xls).

- sheet:

  Sheet name or index for Excel files (default: first sheet).

- col_types:

  Optional column-type spec passed through to the underlying reader;
  default reads everything as text.

- col_names:

  Treat the first row as the header (`TRUE`, the default) or read every
  row as data with positional names (`FALSE`). Use `FALSE` when a
  workbook has title/metadata rows above the real header, then recover
  it with
  [`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md).

## Value

A tibble.
