# Check that key columns contain no NA values

Columns listed but absent from `data` are skipped; absence is handled
separately by
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md).

## Usage

``` r
check_no_na(data, columns, table_name)
```

## Arguments

- data:

  A data frame to check.

- columns:

  Character vector of column names to check.

- table_name:

  Human-readable name of the table, used in failure messages.

## Value

Character vector of failure messages; empty if no NAs found.

## See also

Other validation:
[`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md),
[`check_monotonic()`](https://shepherd70.github.io/tritonIngest/reference/check_monotonic.md),
[`check_range()`](https://shepherd70.github.io/tritonIngest/reference/check_range.md),
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md),
[`check_unique()`](https://shepherd70.github.io/tritonIngest/reference/check_unique.md),
[`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md),
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
