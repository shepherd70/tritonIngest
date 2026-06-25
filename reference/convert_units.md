# Convert mass-concentration or mass-fraction values between common units.

Handles two ladders independently: **mass/volume** (g/L, mg/L, ug/L,
ng/L) and **mass/mass** (g/kg, mg/kg, ug/kg, ng/kg, mg/g, ug/g, ng/g,
the latter being the tissue/sediment units). Conversion stays within a
ladder – mass/volume and mass/mass are not interconvertible without a
density, so a cross-ladder request returns `NA`. The micro prefix is
accepted as either the micro sign (U+00B5, `"\u00b5g/L"`) or Greek small
mu (U+03BC, common from instrument exports); both fold to the same unit.

## Usage

``` r
convert_units(value, from, to)
```

## Arguments

- value:

  Numeric vector.

- from:

  Character vector of source units (recycled to `length(value)`).

- to:

  Single target unit.

## Value

Numeric vector of converted values (`NA` where not convertible).

## Details

Returns the value unchanged when units already match
(case/space-insensitive). When a non-identity conversion cannot be
resolved – an unknown unit or a cross-ladder pair – the result is `NA`
*and a warning is emitted*, so an unsupported unit class is
distinguishable from a value that was simply missing (both would
otherwise be a bare `NA`).
