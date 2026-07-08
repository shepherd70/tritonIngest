# Does a character vector look numeric-ish (allowing censored notation)?

Used by layout detection: a measured-variable column in a wide file
contains numbers and possibly censored entries (`"<DL"`, `">2420"`,
`"ND"`, `"TNTC"`).

## Usage

``` r
is_value_like(x, threshold = 0.8, na_strings = c("-", "--", "n/a", "N/A"))
```

## Arguments

- x:

  Character vector.

- threshold:

  Minimum fraction of non-missing entries that must parse as a number or
  a recognised censored token.

- na_strings:

  Placeholders that mean "not measured" and are excluded from the
  denominator alongside `NA` and `""`. Excel exports commonly write
  `"-"`; before 0.6.0 such a column scored as *not* value-like and a
  wide sheet could lose most of its analyte columns.

## Value

`TRUE`/`FALSE`.
