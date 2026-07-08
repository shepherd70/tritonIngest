# Drop label rows: rows carrying fewer than `min_cells` populated cells.

[`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md)
deliberately keeps every row that is not *fully* blank, because deciding
that a sparse row is not a record needs the schema. But two sparse-row
species are structural, not data, in almost every lab export: the
single-cell **section divider** (`"Physical Tests"`, `"Total Metals"`)
that separates analyte blocks, and the trailing **footnote banner**.
Both carry one populated cell.

## Usage

``` r
drop_label_rows(df, min_cells = 2L)
```

## Arguments

- df:

  A data frame.

- min_cells:

  Minimum number of non-blank cells a row must have to be kept.

## Value

`df` without its label rows.

## Details

This is the generic form of the rule; a caller that knows its schema can
pass a different `min_cells`.
