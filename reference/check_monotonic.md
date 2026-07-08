# Check that a date/numeric column runs monotonically

A sampling series that steps backwards usually means a mistyped year.
Serial 45951 sitting between 45583 and 45588 is a valid Excel date, so
no type or range check can see it – only the ordering can.

## Usage

``` r
check_monotonic(
  data,
  column,
  table_name,
  increasing = TRUE,
  max_gap = NA_real_,
  max_report = 5L
)
```

## Arguments

- data:

  A data frame to check.

- column:

  Name of the column to test. Skipped if absent from `data`.

- table_name:

  Human-readable name of the table, used in failure messages.

- increasing:

  Test for a non-decreasing (`TRUE`, the default) or non-increasing
  sequence.

- max_gap:

  Optional maximum permitted step between consecutive values, in the
  column's own units (days, for a `Date`). `NA` disables the gap check.

- max_report:

  Maximum number of offending positions to name.

## Value

Character vector of failure messages; empty if monotonic.

## See also

Other validation:
[`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md),
[`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md),
[`check_range()`](https://shepherd70.github.io/tritonIngest/reference/check_range.md),
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md),
[`check_unique()`](https://shepherd70.github.io/tritonIngest/reference/check_unique.md),
[`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md),
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
