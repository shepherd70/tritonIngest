# Complete a mapped frame to the full contract schema.

Adds any contract field not already present as a typed all-`NA` column,
in contract order, so downstream code that references optional columns
unconditionally still finds them. Run
[`validate_against_contract()`](https://shepherd70.github.io/tritonIngest/reference/validate_against_contract.md)
on the pre-completion frame so genuinely-missing required fields are
still reported.

## Usage

``` r
complete_to_contract(df, contract)
```

## Arguments

- df:

  A data frame with contract-named columns.

- contract:

  A contract (list of specs or tibble).

## Value

A tibble containing every contract field plus any extra columns already
on `df`, with contract fields ordered first.
