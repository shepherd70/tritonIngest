# Identify a file's real type from its leading bytes.

Returns the *content* type, ignoring the file name. Used by
[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
to refuse a workbook wearing a `.csv` extension (and vice versa) rather
than silently mis-parsing it.

## Usage

``` r
sniff_format(path)
```

## Arguments

- path:

  File path.

## Value

One of `"zip"` (an OOXML workbook: xlsx/xlsm/ods), `"ole2"` (a legacy
binary xls), `"empty"` (zero bytes), or `"text"` (anything else).
