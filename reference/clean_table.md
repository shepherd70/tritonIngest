# Clean a freshly-read table: promote the header and strip junk.

Locates the header row (or uses `header_row`), makes it the column
names, drops everything above it, then removes fully-blank rows and
columns and optionally trims whitespace. Cell *values* are never coerced
– the all-text contract from
[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
is preserved.

## Usage

``` r
clean_table(df, header_row = NULL, trim_ws = TRUE)
```

## Arguments

- df:

  A data frame of all-text, header-less rows (see
  [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)).

- header_row:

  Optional integer: force this row to be the header instead of detecting
  it.

- trim_ws:

  Trim leading/trailing whitespace from header and cell text.

## Value

A tibble with promoted names and structural junk removed.

## Details

Expects a header-less frame, i.e. read with `col_names = FALSE` so the
real header is still a data row to be found. Blank or duplicated header
names are filled (`col_<position>`) and made unique rather than silently
collapsed. Only fully blank rows/columns are dropped (see the note in
`clean.R`).
