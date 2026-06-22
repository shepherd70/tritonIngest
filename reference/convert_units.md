# Convert mass-concentration values between common units.

Handles the concentration ladder (g/L, mg/L, ug/L, ng/L); returns the
value unchanged when units already match (case/space-insensitive) and
`NA` when the conversion is not defined (so the caller can treat a
mismatch as indeterminate rather than silently comparing incompatible
units).

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
