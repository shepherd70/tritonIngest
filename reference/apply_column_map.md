# Apply a column mapping to a source data frame.

Selects the mapped source columns, renames them to their contract field
names, and (optionally) coerces each to its declared type. Fields whose
mapping is `NA`/missing are dropped – use
[`validate_against_contract()`](https://shepherd70.github.io/tritonIngest/reference/validate_against_contract.md)
afterwards to flag missing required fields. Unreferenced source columns
are discarded, so downstream code sees only contract-named columns.

## Usage

``` r
apply_column_map(
  df,
  mapping,
  contract,
  coerce = TRUE,
  warn_coercion = NULL,
  loss = c("error", "warn", "allow")
)
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

- warn_coercion:

  Warn when coercion turns non-missing source values into `NA`.
  Deprecated; use `loss`.

- loss:

  Policy when coercion would discard populated values: error by default,
  or explicitly warn/allow.

## Value

A tibble with contract-named (subset of) columns.

## Coercion is lossy, and says so

Coercing a `numeric` field runs
[`as.numeric()`](https://rdrr.io/r/base/numeric.html), which turns every
censored result (`"<0.25"`, `"ND"`, `">2420"`) into `NA`. That is
exactly the information
[`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
exists to preserve, and the contract path does not call it. Parse first,
then map the parsed columns. When coercion does drop non-missing values,
`warn_coercion` reports the field, the count and a few example tokens
rather than letting them vanish.
