# Is a mapped frame ready to use for a contract?

`TRUE` when no field has `severity == "error"`.

## Usage

``` r
contract_is_ready(df, contract)
```

## Arguments

- df:

  A data frame with contract-named columns.

- contract:

  A contract (list of specs or tibble).

## Value

Logical scalar.
