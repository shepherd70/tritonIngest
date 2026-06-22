# Coerce field specs into a contract tibble.

Accepts a list of
[`cf_field()`](https://shepherd70.github.io/tritonIngest/reference/cf_field.md)
specs, or an already-built contract tibble (idempotent), so engine
functions can take either form.

## Usage

``` r
as_contract(x)
```

## Arguments

- x:

  A list of
  [`cf_field()`](https://shepherd70.github.io/tritonIngest/reference/cf_field.md)
  specs, or a contract tibble.

## Value

A tibble with columns `field`, `type`, `required`, `synonyms`
(list-column), `description`.
