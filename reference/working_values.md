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
  fraction = 0.5
)
```

## Arguments

- value:

  Numeric vector (NA where censored).

- censored:

  Logical vector (NA = unparseable).

- detection_limit:

  Numeric vector of DLs.

- method:

  Censoring method; currently only `"substitution"`.

- fraction:

  Substitution fraction (0, 0.5, or 1).

## Value

Numeric vector with censored entries handled per method.
