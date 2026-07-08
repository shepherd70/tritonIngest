# Heuristically detect whether a table is long/tidy or wide.

Long signals: a parameter-ish column name AND a value-ish column name,
or a single value-like column. Wide signals: two or more value-like
columns (variables spread across columns). The caller can override the
result.

## Usage

``` r
detect_layout(
  df,
  param_names = c("parameter", "parameters", "param", "params", "analyte", "analytes",
    "characteristic", "characteristics", "characteristicname", "variable", "variables",
    "constituent", "constituents"),
  value_names = c("value", "values", "result", "results", "resultvalue", "value_raw",
    "concentration", "concentrations", "conc", "measurement", "measurements"),
  na_strings = c("-", "--", "n/a", "N/A")
)
```

## Arguments

- df:

  A data frame (typically read all-text via
  [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)).

- param_names, value_names:

  Character vectors of lowercase column names that signal a long-format
  parameter / value column. Matched after lowercasing and
  whitespace-trimming the data's names. Override to match a domain's
  vocabulary.

- na_strings:

  Placeholders treated as missing by
  [`is_value_like()`](https://shepherd70.github.io/tritonIngest/reference/is_value_like.md).

## Value

A list: `layout` (`"long"`/`"wide"`/`"transposed"`), `value_like_cols`,
`reason`.

## Details

Column names are matched case-insensitively and after trimming
surrounding whitespace, so a header exported as `"Analyte "` (a trailing
space is common in lab reports) still hits the vocabulary. The default
vocabularies carry both singular and plural forms
(`"result"`/`"results"`, `"analyte"`/`"analytes"`, ...) because labs are
inconsistent: an ALS export, for instance, labels its value column
`"Results"`. Missing the plural would drop the long signal and, when two
or more numeric columns are present (value + detection limit + a numeric
QC-lot id), misclassify the table as wide.

## Transposed tables

A third shape exists in the wild: analytes down the first column and one
*sample* per column (a lab's "results matrix"). Its columns are numeric,
so this function reports `"wide"` and a caller melting on
`value_like_cols` would emit one `parameter` per sample.
[`looks_transposed()`](https://shepherd70.github.io/tritonIngest/reference/looks_transposed.md)
tests for that shape and
[`transpose_table()`](https://shepherd70.github.io/tritonIngest/reference/transpose_table.md)
converts it; `detect_layout()` reports `layout = "transposed"` when the
test fires.
