# Check that a set of columns forms a unique key

The validation kernel is otherwise column-level: it counts NAs and
compares classes, but never looks at a *record*. A repeated
`(date, time)` pair – a double-entered sampling event, or two field
sheets merged twice – passes every other check silently.

## Usage

``` r
check_unique(data, columns, table_name, max_report = 5L)
```

## Arguments

- data:

  A data frame to check.

- columns:

  Character vector of column names forming the key. Columns absent from
  `data` are skipped (see
  [`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md)).

- table_name:

  Human-readable name of the table, used in failure messages.

- max_report:

  Maximum number of offending keys to name in the message.

## Value

Character vector of failure messages; empty if the key is unique.

## See also

Other validation:
[`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md),
[`check_monotonic()`](https://shepherd70.github.io/tritonIngest/reference/check_monotonic.md),
[`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md),
[`check_range()`](https://shepherd70.github.io/tritonIngest/reference/check_range.md),
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md),
[`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md),
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
