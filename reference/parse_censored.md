# Parse raw result text into value / censoring / limit / qualifier.

Recognises left-censored (`"<x"`, `"ND"`), right-censored (`">x"`,
`"TNTC"`) and detected values, and separates any laboratory qualifier
flag from the number it decorates (`"178d"` -\> value 178, qualifier
`"d"`).

## Usage

``` r
parse_censored(
  value_raw,
  detection_limit = NULL,
  na_strings = c("-", "--", "n/a", "N/A"),
  nd_tokens = ND_TOKENS,
  over_tokens = OVER_TOKENS,
  qualifiers = TRUE
)
```

## Arguments

- value_raw:

  Character vector of raw results as read from file.

- detection_limit:

  Optional numeric vector (recycled if length 1) from a separate DL/RL
  column; used for bare tokens (`"ND"`) and checked for consistency
  against `"<DL"` notation.

- na_strings:

  Values (compared case-insensitively after trimming) that mean "not
  measured" rather than a result. Excel exports commonly write `"-"`.

- nd_tokens, over_tokens:

  Bare left- / right-censored markers.

- qualifiers:

  Extract leading/trailing laboratory flags from an otherwise numeric
  cell. `FALSE` restores the strict behaviour in which `"178d"` is
  unparseable.

## Value

A tibble: `value` (dbl, NA where censored/unparseable), `censored` (lgl:
TRUE when the true value is not directly observed, in either direction;
NA where unparseable), `censor_direction` (`"none"`/`"left"`/`"right"`,
NA where unparseable), `detection_limit` (dbl, left-censored rows only),
`censor_limit` (dbl, the bound in either direction), `qualifier` (chr,
NA when none), `parse_note` (chr, NA when clean).

## Two limit columns, on purpose

`detection_limit` keeps its original meaning – the detection/reporting
limit below which a result was not detected. It is populated for
left-censored rows and is **`NA` for right-censored ones**: a `">2420"`
result has no detection limit, it has a quantitation ceiling. That
ceiling lives in `censor_limit`, which carries the numeric bound for
*either* direction.

The split is what makes the default safe. A caller that does not yet
know about right-censoring calls
`apply_substitution(value, censored, detection_limit)`; the
right-censored rows have `detection_limit = NA`, so they drop to `NA`
rather than being substituted as `fraction * ceiling` – which would
fabricate a number *below* the true value. Pass `censor_direction` and
`censor_limit` to use them properly.
