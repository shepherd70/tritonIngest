# Working numeric values for a censoring method.

A single censoring "switch" for code that needs a plain numeric vector.
Maps (value, censored, detection_limit) to working values under the
chosen non-detect handling. Only substitution is supported here; robust
group-level estimators (KM/ROS) live in the consuming package.

## Usage

``` r
working_values(
  value,
  censored,
  detection_limit,
  method = c("substitution"),
  fraction = 0.5,
  censor_direction = NULL,
  censor_limit = NULL
)
```

## Arguments

- value:

  Numeric vector (NA where censored), **or** a tibble returned by
  [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md),
  in which case the remaining columns are taken from it.

- censored:

  Logical vector (NA = unparseable).

- detection_limit:

  Numeric vector of detection limits.

- method:

  Censoring method; currently only `"substitution"`.

- fraction:

  Substitution fraction (0, 0.5, or 1).

- censor_direction:

  Optional `"none"`/`"left"`/`"right"` vector; see
  [`apply_substitution()`](https://shepherd70.github.io/tritonIngest/reference/apply_substitution.md).

- censor_limit:

  Optional numeric vector of censoring bounds; see
  [`apply_substitution()`](https://shepherd70.github.io/tritonIngest/reference/apply_substitution.md).

## Value

Numeric vector with censored entries handled per method.

## Details

Pass the whole
[`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
tibble as `value` to handle both censoring directions correctly with no
further arguments: `working_values(parse_censored(x))`. The vector form
is kept for callers that carry the columns separately; without
`censor_direction` it treats every censored entry as left-censored (see
[`apply_substitution()`](https://shepherd70.github.io/tritonIngest/reference/apply_substitution.md)).
