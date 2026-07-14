# Is a mapped frame ready to use for a contract?

Strict readiness requires the minimum row count and no unresolved field
warnings or errors. Structural-only readiness is available explicitly.

## Usage

``` r
contract_is_ready(
  df,
  contract,
  policy = c("strict", "structure"),
  min_rows = 1L,
  max_invalid_fraction = 0,
  allow_warnings = FALSE
)
```

## Arguments

- df:

  A data frame with contract-named columns.

- contract:

  A contract (list of specs or tibble).

- policy:

  `"strict"` or explicit structural-only `"structure"` policy.

- min_rows:

  Minimum number of rows required.

- max_invalid_fraction:

  Maximum tolerated invalid populated fraction.

- allow_warnings:

  Treat warning-only validation results as ready.

## Value

Logical scalar.
