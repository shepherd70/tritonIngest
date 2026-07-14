# Build a structured tabular-ingestion diagnostic

Build a structured tabular-ingestion diagnostic

## Usage

``` r
tabular_diagnostic(
  code,
  severity = c("info", "warning", "error"),
  stage,
  message,
  requires_review = severity[1] != "info",
  table = NULL,
  sheet = NULL,
  column = NULL,
  source_rows = integer(0),
  cells = character(0),
  details = list()
)
```

## Arguments

- code:

  Stable snake-case diagnostic code.

- severity:

  One of `"info"`, `"warning"`, or `"error"`.

- stage:

  Processing stage.

- message:

  Human-readable explanation.

- requires_review:

  Does this issue require human review?

- table, sheet, column:

  Optional location labels.

- source_rows:

  One-based source row numbers.

- cells:

  Spreadsheet cell references.

- details:

  Named list of machine-readable details.

## Value

A named list conforming to `tabular-diagnostic/v1`.
