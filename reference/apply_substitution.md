# Apply a simple substitution rule to censored values.

Returns a numeric vector where censored entries are replaced by a
working value; detected entries pass through unchanged. Transparent and
widely used, but can bias variance estimates.

## Usage

``` r
apply_substitution(
  value,
  censored,
  detection_limit,
  fraction = 0.5,
  censor_direction = NULL,
  censor_limit = NULL
)
```

## Arguments

- value:

  Numeric vector (NA where censored).

- censored:

  Logical vector, the same length as `value`.

- detection_limit:

  Numeric vector of detection limits (length 1, recycled, or the same
  length as `value`).

- fraction:

  Substitution fraction for left-censored values: 0.5 (default, = 1/2
  DL), 1 (DL), or 0.

- censor_direction:

  Optional character vector of `"none"`/`"left"`/ `"right"`, the same
  length as `value`.

- censor_limit:

  Optional numeric vector of censoring bounds, used for right-censored
  entries. Required whenever `censor_direction` names any `"right"`
  entry.

## Value

Numeric vector with censored entries substituted (NA where the limit
itself is unknown).

## Details

Left-censored entries become `fraction * detection_limit`.
Right-censored entries become `censor_limit` itself – the true value is
known only to exceed the ceiling, so substituting a fraction of it would
understate the result.

## Safe by default

When `censor_direction` is `NULL` every censored entry is treated as
**left**-censored, which reproduces the pre-0.6.0 behaviour. That is
safe because
[`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
leaves `detection_limit` as `NA` for right-censored rows: a caller that
does not pass `censor_direction` gets `NA` for them, not a fabricated
`fraction * ceiling`. Pass both `censor_direction` and `censor_limit` –
or, more simply, pass the whole
[`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
tibble to
[`working_values()`](https://shepherd70.github.io/tritonIngest/reference/working_values.md)
– to substitute right-censored results properly.
