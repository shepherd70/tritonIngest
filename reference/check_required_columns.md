# Check that required columns are present in a data frame

Check that required columns are present in a data frame

## Usage

``` r
check_required_columns(data, required, table_name)
```

## Arguments

- data:

  A data frame to check.

- required:

  Character vector of required column names. May be the names of a named
  type-spec vector (e.g. `c(reach_id = "character")`), in which case the
  names are used; an unnamed character vector is used as-is.

- table_name:

  Human-readable name of the table, used in failure messages.

## Value

Character vector of failure messages; empty if all required columns are
present.

## See also

Other validation:
[`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md),
[`check_monotonic()`](https://shepherd70.github.io/tritonIngest/reference/check_monotonic.md),
[`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md),
[`check_range()`](https://shepherd70.github.io/tritonIngest/reference/check_range.md),
[`check_unique()`](https://shepherd70.github.io/tritonIngest/reference/check_unique.md),
[`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md),
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
