# Melt a wide table (variables as columns) to long form.

Errors if a retained id column is named `parameter`, `value_raw`, or
`units` (the reshape's output names) rather than silently overwriting
it.

## Usage

``` r
melt_wide(
  df,
  param_cols,
  id_cols = setdiff(names(df), param_cols),
  units = NULL,
  na_strings = c("-", "--", "n/a", "N/A")
)
```

## Arguments

- df:

  Wide data frame.

- param_cols:

  Character vector of measured-variable column names to melt.

- id_cols:

  Columns to keep as identifiers; default everything else.

- units:

  Optional named character vector mapping parameter -\> units, since
  wide files usually carry units in a header or codebook rather than per
  cell. Unmatched parameters get NA units.

- na_strings:

  Cell values dropped alongside blanks as "not measured". Excel exports
  commonly write `"-"`; before 0.6.0 those rows survived the melt and
  became `"unparseable result text: '-'"` downstream.

## Value

Long tibble with columns: `id_cols...`, `parameter`, `value_raw`,
`units`.
