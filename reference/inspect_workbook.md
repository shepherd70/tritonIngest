# Inspect formula and merge features in an OOXML workbook

Reads workbook XML directly, without evaluating formulas or changing the
source. Formula cells are counted per worksheet, along with formula
cells that have no cached `<v>` result and merged-cell ranges. This is
intentionally a small safety inventory; the Python cleanup service
remains responsible for detailed style, formula-text, and
review-workflow inventory.

## Usage

``` r
inspect_workbook(path, sheets = NULL)
```

## Arguments

- path:

  Path to an `.xlsx` workbook.

- sheets:

  Optional sheet names or one-based positions to inspect. The default
  scans every worksheet.

## Value

A tibble with sheet identity/visibility and integer columns
`formula_cells`, `formula_gaps`, and `merged_ranges`.
