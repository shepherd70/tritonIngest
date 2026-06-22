# Does a character vector look numeric-ish (allowing non-detect notation)?

Used by layout detection: a measured-variable column in a wide file
contains numbers and possibly non-detect entries (`"<DL"`, `"ND"`).

## Usage

``` r
is_value_like(x, threshold = 0.8)
```

## Arguments

- x:

  Character vector.

- threshold:

  Minimum fraction of non-missing entries that must parse as a number or
  a recognised non-detect token.

## Value

`TRUE`/`FALSE`.
