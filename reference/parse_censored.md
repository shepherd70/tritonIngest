# Parse raw result text into value / censored / detection_limit.

Parse raw result text into value / censored / detection_limit.

## Usage

``` r
parse_censored(value_raw, detection_limit = NULL)
```

## Arguments

- value_raw:

  Character vector of raw results as read from file.

- detection_limit:

  Optional numeric vector (recycled if length 1) from a separate DL/RL
  column; used for token non-detects (`"ND"`) and checked for
  consistency against `"<DL"` notation.

## Value

A tibble: `value` (dbl, NA where censored/unparseable), `censored` (lgl,
NA where unparseable), `detection_limit` (dbl), `parse_note` (chr, NA
when clean).
