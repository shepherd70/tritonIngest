# List the worksheets of a workbook, with their visibility.

[`readxl::excel_sheets()`](https://readxl.tidyverse.org/reference/excel_sheets.html)
returns every sheet's name but not whether Excel hides it: a
`veryHidden` sheet in position 1 is what
[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
reads by default, with no signal. This reads `xl/workbook.xml` directly
to recover the `state` attribute.

## Usage

``` r
list_sheets(path)
```

## Arguments

- path:

  Path to an `.xlsx`/`.xlsm`/`.xls` workbook.

## Value

A tibble with `index` (1-based sheet position, as accepted by
`read_tabular(sheet = )`), `name`, and `visible` (`"visible"`,
`"hidden"`, `"veryHidden"`, or `NA`).

## Details

For a legacy `.xls` (OLE2) workbook, or any file whose `workbook.xml`
cannot be parsed, the names still come back but `visible` is `NA`.
