# Check that columns have expected types

Validates type only for columns that are present; absence is handled
separately by
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md).

## Usage

``` r
check_column_types(data, types, table_name)
```

## Arguments

- data:

  A data frame to check.

- types:

  Named character vector mapping column names to expected type specs
  (see
  [`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md)).

- table_name:

  Human-readable name of the table, used in failure messages.

## Value

Character vector of failure messages; empty if all present columns are
of the correct type.

## See also

Other validation:
[`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md),
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md),
[`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md),
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
