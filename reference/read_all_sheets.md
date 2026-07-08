# Read every worksheet of a workbook.

The multi-sheet counterpart to
[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md),
which reads exactly one sheet. Sheets that fail to read (an empty sheet,
a chart sheet) are reported and skipped rather than aborting the whole
workbook.

## Usage

``` r
read_all_sheets(
  path,
  col_names = TRUE,
  col_types = NULL,
  include_hidden = TRUE,
  sheets = NULL
)
```

## Arguments

- path:

  Path to a workbook.

- col_names, col_types:

  Passed to
  [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md).

- include_hidden:

  Read `hidden` / `veryHidden` sheets too (the default). Set `FALSE` to
  read only what a user would see in Excel.

- sheets:

  Optional character vector of sheet names, or integer positions, to
  restrict the read to.

## Value

A named list of tibbles, one per sheet read, in workbook order. Each
carries a `sheet_visibility` attribute.
