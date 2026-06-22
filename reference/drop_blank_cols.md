# Drop fully-blank columns from a data frame.

A column is blank when every cell is `NA` or empty after trimming
whitespace. Removes the empty spacer columns common in spreadsheet
exports.

## Usage

``` r
drop_blank_cols(df)
```

## Arguments

- df:

  A data frame.

## Value

`df` without its fully-blank columns.
