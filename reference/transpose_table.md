# Transpose an analyte-by-sample results matrix into a tidy long table.

Converts the shape
[`looks_transposed()`](https://shepherd70.github.io/tritonIngest/reference/looks_transposed.md)
detects. The first `n_label_cols` columns describe each analyte (its
name, its units, guideline columns, ...) and the remaining columns are
one per sample. `header_rows` names the rows above the analyte block
that describe each sample (sample id, date, time, location); each
becomes a column of the output.

## Usage

``` r
transpose_table(
  df,
  header_rows,
  body_rows,
  label_cols,
  sample_cols,
  na_strings = c("-", "--", "n/a", "N/A")
)
```

## Arguments

- df:

  A data frame read all-text with the header **not** promoted
  (`read_tabular(col_names = FALSE)`), so the sample-describing rows are
  data.

- header_rows:

  Named integer vector: output column name -\> row index, e.g.
  `c(location = 1, lab_id = 2, sample_date = 3, sample_time = 4)`.

- body_rows:

  Integer vector of rows holding analyte results.

- label_cols:

  Named integer vector: output column name -\> column index for the
  per-analyte label columns, e.g. `c(parameter = 1, units = 2)`.

- sample_cols:

  Integer vector of columns holding sample results.

- na_strings:

  Cell values dropped as "not measured".

## Value

A long tibble: one row per (sample, analyte), with the `header_rows` and
`label_cols` names as columns plus `value_raw`.
