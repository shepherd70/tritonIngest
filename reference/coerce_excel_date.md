# Coerce mixed Excel-serial / ISO-string dates to Date.

Worksheet date columns ingested from Excel sometimes arrive as a mix of
Excel serial numbers (e.g. `"45909"` or `45909`) and ISO date strings
(e.g. `"2023-08-22"`), depending on how each cell was formatted. A naive
[`as.Date()`](https://rdrr.io/r/base/as.Date.html) mangles the serials
and a naive serial conversion drops the ISO strings to `NA`. This
detects each element's encoding and coerces both to a single `Date`
vector (1900 date system, origin 1899-12-30), leaving genuinely
missing/unparseable values as `NA`.

## Usage

``` r
coerce_excel_date(x)
```

## Arguments

- x:

  A vector (numeric or character) of Excel-serial numbers and/or ISO
  `"YYYY-MM-DD"` strings.

## Value

A `Date` vector the same length as `x`.
