# Clean a freshly-read table: promote the header and strip junk.

Locates the header row (or uses `header_row`/`header_rows`), makes it
the column names, drops everything above it, then removes fully-blank
rows and columns and optionally trims whitespace. Cell *values* are
never coerced – the all-text contract from
[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
is preserved.

## Usage

``` r
clean_table(
  df,
  header_row = NULL,
  header_rows = NULL,
  trim_ws = TRUE,
  drop_labels = FALSE,
  sep = " "
)
```

## Arguments

- df:

  A data frame of all-text, header-less rows (see
  [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)).

- header_row:

  Optional integer: force this row to be the header instead of detecting
  it.

- header_rows:

  Optional integer vector of two or more rows forming a multi-row
  header; their non-blank cells are pasted down each column. Takes
  precedence over `header_row`. The body starts after
  `max(header_rows)`.

- trim_ws:

  Trim leading/trailing whitespace from header and cell text.

- drop_labels:

  Also drop rows with fewer than two populated cells (see
  [`drop_label_rows()`](https://shepherd70.github.io/tritonIngest/reference/drop_label_rows.md)).

- sep:

  Separator used to join the pieces of a multi-row header.

## Value

A tibble with promoted names and structural junk removed.

## Details

Expects a header-less frame, i.e. read with `col_names = FALSE` so the
real header is still a data row to be found. Blank header names are
filled (`col_<position>`) and duplicates made unique, both with a
warning: a duplicated header is usually a mislabelled column, and a
blank one usually means the promoted row was not the whole header.

## What this does not do

Only fully-blank rows are dropped. An embedded metadata row – a
`"Permit limit"` row whose analyte cells are ordinary numbers – survives
and becomes a record. Pass `drop_labels = TRUE` for the single-cell
section dividers and footnote banners; anything richer needs the schema,
so filter it in the consumer. A paginated print report with a *repeated*
header every N rows is not a single table at all: split it on the
repeated header rows before calling this.
