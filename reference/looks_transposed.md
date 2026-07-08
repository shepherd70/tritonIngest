# Does this table hold analytes down a column and samples across the header?

A lab "results matrix" puts one analyte per row and one *sample* per
column. Its data columns are numeric, so
[`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
would otherwise call it `"wide"` and a caller melting on
`value_like_cols` would produce one `parameter` per sample rather than
per analyte.

## Usage

``` r
looks_transposed(
  df,
  param_names = c("parameter", "parameters", "param", "analyte", "analytes",
    "characteristic", "constituent", "variable", "determinand"),
  min_labels = 5L,
  min_dup_frac = 0.3,
  na_strings = c("-", "--", "n/a", "N/A")
)
```

## Arguments

- df:

  A data frame.

- param_names:

  Vocabulary of parameter-column labels (see
  [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)).

- min_labels:

  Minimum distinct non-numeric labels required in column 1.

- min_dup_frac:

  Minimum duplicated fraction of the header names.

- na_strings:

  Placeholders treated as missing.

## Value

A list: `transposed` (lgl), `reason` (chr).

## Details

Two independent signals, either of which is enough:

- a `param_names` token (`"analyte"`, `"parameter"`, ...) appears among
  the **values** of the first column rather than as a column name; or

- at least `min_dup_frac` of the header names are duplicates (the same
  station or sample point sampled repeatedly), while the first column is
  not value-like and carries several distinct labels.

The second signal only fires on a header read with
`.name_repair = "minimal"`; a reader that has already made the names
unique has destroyed the evidence.
