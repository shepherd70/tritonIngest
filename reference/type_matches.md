# Check whether an actual R class satisfies an expected type spec

`"numeric"` accepts numeric, double, and integer; `"integer"` is strict;
`"Date"` (or contract-style lowercase `"date"`) requires the Date class;
`"logical"` and `"character"` are exact. Any other spec falls back to an
exact class match.

## Usage

``` r
type_matches(actual, expected)
```

## Arguments

- actual:

  First element of [`class()`](https://rdrr.io/r/base/class.html) of the
  column being checked.

- expected:

  Expected type spec string.

## Value

Logical scalar.

## See also

Other validation:
[`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md),
[`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md),
[`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md),
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
