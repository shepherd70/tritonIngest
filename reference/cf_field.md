# Build one contract field specification.

Build one contract field specification.

## Usage

``` r
cf_field(
  name,
  type = c("character", "numeric", "integer", "date"),
  required = FALSE,
  synonyms = character(0),
  description = ""
)
```

## Arguments

- name:

  Contract field name (the canonical output column name).

- type:

  One of `"character"`, `"numeric"`, `"integer"`, `"date"`.

- required:

  Logical; is the field required for the data to be usable?

- synonyms:

  Character vector of alternative source-column names that should map to
  this field (matched after name normalisation).

- description:

  Short human-readable description.

## Value

A field-spec list.
