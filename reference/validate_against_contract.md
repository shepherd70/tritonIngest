# Validate a (mapped) data frame against a contract.

Reports, per contract field, whether it is present, populated, and valid
for its declared type.

## Usage

``` r
validate_against_contract(
  df,
  contract,
  policy = c("strict", "structure"),
  max_invalid_fraction = 0
)
```

## Arguments

- df:

  A data frame with contract-named columns.

- contract:

  A contract (list of specs or tibble).

- policy:

  `"strict"` validates values and structure; `"structure"` checks only
  presence and population.

- max_invalid_fraction:

  Maximum tolerated fraction of invalid populated values before a field
  becomes an error.

## Value

A tibble: `field`, `required`, `status`, `severity`
(`"error"`/`"warning"`/`"ok"`), `issue`, and total/populated/missing/
invalid counts plus the invalid fraction.
