# Abort with a classed error listing all collected validation failures

Standardizes the collect-all-failures-then-abort pattern: run every
check, concatenate the returned failure messages, and call this once.
Does nothing when `failures` is empty, so it can be called
unconditionally at the end of a validator.

## Usage

``` r
validation_abort(failures, class = "triton_validation_error", header = NULL)
```

## Arguments

- failures:

  Character vector of failure messages (possibly empty).

- class:

  Additional condition class for the error, prepended to
  `"triton_validation_error"` so callers can keep package-specific
  classes (e.g. `"cpue_validation_error"`).

- header:

  Optional header line; defaults to a count of issues.

## Value

Invisibly `TRUE` when `failures` is empty; otherwise signals an error of
class `c(class, "triton_validation_error")` whose `failures` field holds
the full message vector.

## See also

Other validation:
[`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md),
[`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md),
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md),
[`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md)
