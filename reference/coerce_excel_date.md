# Coerce mixed Excel-serial / date-string values to Date.

Worksheet date columns ingested from Excel often arrive as a mix of
Excel serial numbers (e.g. `"45909"` or `45909`) and date strings (e.g.
`"2023-08-22"`), depending on how each cell was formatted. A naive
[`as.Date()`](https://rdrr.io/r/base/as.Date.html) mangles the serials
and a naive serial conversion drops the strings to `NA`. This detects
each element's encoding and coerces both to a single `Date` vector,
leaving genuinely missing/unparseable values as `NA`.

## Usage

``` r
coerce_excel_date(
  x,
  formats = c("%Y-%m-%d", "%Y/%m/%d"),
  origin = "1899-12-30",
  serial_range = c(1, 2958465)
)
```

## Arguments

- x:

  A vector (numeric or character) of Excel-serial numbers and/or date
  strings.

- formats:

  Character vector of
  [`strptime()`](https://rdrr.io/r/base/strptime.html) formats tried, in
  order, for string (non-serial) elements. Defaults to year-first ISO
  layouts.

- origin:

  Date origin for Excel serials: `"1899-12-30"` (1900 system, default)
  or `"1904-01-01"` (1904 system).

- serial_range:

  Length-2 `c(min, max)` bounding which numbers are treated as Excel
  serials. Defaults to the full valid Excel range; tighten it (e.g.
  `c(10000, 60000)`) when bare year-like integers like `"2024"` would
  otherwise be misread as serials.

## Value

A `Date` vector the same length as `x`.

## Details

Detection is by value: anything that parses as a number *within*
`serial_range` is treated as an Excel serial; every other non-empty
element is parsed against `formats` in order (first match wins, per
element). The default `formats` are the unambiguous **year-first**
layouts; pass `formats` for day- or month-first data (e.g. `"%d/%m/%Y"`)
rather than relying on a guess, which would silently misread ambiguous
values such as `"05/06/2024"`. A non-empty value matching neither a
serial nor any format becomes `NA` *with a warning*, so a
silently-dropped date column does not pass unnoticed.

The Excel **1900** date system is the default (`origin = "1899-12-30"`,
so serial 1 is 1900-01-01); pass `origin = "1904-01-01"` for a workbook
saved under the Mac/1904 system.
