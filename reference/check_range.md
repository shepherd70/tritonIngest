# Check that numeric columns fall inside declared bounds

Catches the physically impossible values that type checking cannot: a pH
of 42.4, a percentage survival of 150, a negative concentration.

## Usage

``` r
check_range(data, bounds, table_name, max_report = 5L)
```

## Arguments

- data:

  A data frame to check.

- bounds:

  Named list mapping column name to `c(min, max)`. Use `NA` for an open
  end, e.g. `list(concentration = c(0, NA))`. Columns absent from `data`
  are skipped.

- table_name:

  Human-readable name of the table, used in failure messages.

- max_report:

  Maximum number of offending values to name per column.

## Value

Character vector of failure messages; empty if every value is in range.

## See also

Other validation:
[`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md),
[`check_monotonic()`](https://shepherd70.github.io/tritonIngest/reference/check_monotonic.md),
[`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md),
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md),
[`check_unique()`](https://shepherd70.github.io/tritonIngest/reference/check_unique.md),
[`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md),
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
