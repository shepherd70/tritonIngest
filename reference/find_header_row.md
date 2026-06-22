# Find the most likely header row in a header-less table.

Given a frame read with every row as data
(`read_tabular(path, col_names = FALSE)`), guess which row holds the
column names. Leading blank rows and sparse title/metadata rows are
skipped; the header is taken to be the first well-populated row whose
own cells look like names rather than values, and that has data beneath
it. Reuses
[`is_value_like()`](https://shepherd70.github.io/tritonIngest/reference/is_value_like.md)
to tell names from values.

## Usage

``` r
find_header_row(df, max_scan = 20L)
```

## Arguments

- df:

  A data frame of all-text, header-less rows.

- max_scan:

  Maximum number of leading rows to examine for the header.

## Value

Integer row index of the header, or `NA_integer_` if none is found.

## Details

This is a heuristic and is meant to be overridable: when nothing is
convincing it returns `NA` so the caller can fall back or pass an
explicit `header_row` to
[`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md).
