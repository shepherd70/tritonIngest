# Drop fully-blank rows from a data frame.

A row is blank when every cell is `NA` or empty after trimming
whitespace.

## Usage

``` r
drop_blank_rows(df)
```

## Arguments

- df:

  A data frame.

## Value

`df` without its fully-blank rows.
