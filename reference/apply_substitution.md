# Apply a simple substitution rule to censored values.

Returns a numeric vector where censored entries are replaced by
`fraction * detection_limit`; detected entries pass through unchanged.
Transparent and widely used, but can bias variance estimates.

## Usage

``` r
apply_substitution(value, censored, detection_limit, fraction = 0.5)
```

## Arguments

- value:

  Numeric vector (NA where censored).

- censored:

  Logical vector.

- detection_limit:

  Numeric vector of DLs.

- fraction:

  Substitution fraction: 0.5 (default, = 1/2 DL), 1 (DL), or 0.

## Value

Numeric vector with censored entries substituted (NA where the DL itself
is unknown).
