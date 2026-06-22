# Apply a column mapping to a source data frame.

Selects the mapped source columns, renames them to their contract field
names, and (optionally) coerces each to its declared type. Fields whose
mapping is `NA`/missing are dropped — use
[`validate_against_contract()`](https://shepherd70.github.io/tritonIngest/reference/validate_against_contract.md)
afterwards to flag missing required fields. Unreferenced source columns
are discarded, so downstream code sees only contract-named columns.

## Usage

``` r
apply_column_map(df, mapping, contract, coerce = TRUE)
```

## Arguments

- df:

  A source data frame.

- mapping:

  Named list/character vector: contract field -\> source column.

- contract:

  A contract (list of specs or tibble).

- coerce:

  Logical; coerce each output column to its declared type.

## Value

A tibble with contract-named (subset of) columns.
