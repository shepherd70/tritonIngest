# Auto-map source columns onto a contract.

For each contract field, picks the best source column by: (1) normalised
exact match on the field name, (2) normalised match against the field's
synonyms, (3) optionally, a fuzzy match
([`utils::adist`](https://rdrr.io/r/utils/adist.html)) within an
edit-distance budget. A source column is used at most once; earlier
(higher-priority) fields win ties, so the mapping depends on contract
field **order**.

## Usage

``` r
auto_map(source_cols, contract, max_distance = 0L, warn = TRUE)
```

## Arguments

- source_cols:

  Character vector of column names from the source data.

- contract:

  A contract (list of specs or tibble).

- max_distance:

  Integer max edit distance for the fuzzy fallback. `0` (default)
  disables fuzzy matching.

- warn:

  Emit warnings for fuzzy matches and exact/synonym ambiguity.

## Value

A named list, one element per contract field, holding the matched
source-column name or `NA_character_`.

## Fuzzy matching is opt-in

`max_distance` defaults to `0` (exact and synonym matching only). Edit
distance over short, systematically-related analyte names is unsafe:
`"LEPH_C10_C19"` is distance 1 from `"EPH_C10_C19"` but distance 9 from
the correct `"LEPH_C10_C19_less_PAH"`, and a two-character synonym such
as `"dl"` is distance 2 from a `"pH"` column. Set `max_distance = 2L` to
restore the pre-0.6.0 behaviour; every fuzzy match is then reported with
a warning.

## Exact names outrank synonyms

A contract field always binds to a column whose *name* matches it, even
when a synonym matches a different column. That is intended – but it is
also how a column innocently named `Analyte` that holds a sample-matrix
label (`"Effluent"`) captures the `analyte` field ahead of the
`parameter` column holding the real analyte names. When both are
present, `auto_map()` warns.
