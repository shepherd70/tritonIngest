# Validate a (mapped) data frame against a contract.

Reports, per contract field, whether it is present and usable. Statuses:
`"ok"`, `"missing"` (column absent), `"all_na"` (present but every value
NA), and `"type_warn"` (declared numeric/integer but \>50%
non-coercible).

## Usage

``` r
validate_against_contract(df, contract)
```

## Arguments

- df:

  A data frame with contract-named columns.

- contract:

  A contract (list of specs or tibble).

## Value

A tibble: `field`, `required`, `status`, `severity`
(`"error"`/`"warning"`/`"ok"`), `issue` (NA when ok).
