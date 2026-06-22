# Auto-map source columns onto a contract.

For each contract field, picks the best source column by: (1) normalised
exact match on the field name, (2) normalised match against the field's
synonyms, (3) fuzzy match
([`utils::adist`](https://rdrr.io/r/utils/adist.html)) within a small
edit-distance budget. A source column is used at most once; earlier
(higher-priority) fields win ties.

## Usage

``` r
auto_map(source_cols, contract, max_distance = 2L)
```

## Arguments

- source_cols:

  Character vector of column names from the source data.

- contract:

  A contract (list of specs or tibble).

- max_distance:

  Integer max edit distance for the fuzzy fallback; set to 0 to disable
  fuzzy matching.

## Value

A named list, one element per contract field, holding the matched
source-column name or `NA_character_`.
