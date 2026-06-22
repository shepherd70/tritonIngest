# Changelog

## tritonIngest 0.4.3

- [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
  now recognises plural parameter/value column names (`"results"`,
  `"values"`, `"analytes"`, `"parameters"`, …) and trims surrounding
  whitespace from column names before matching. Lab exports such as ALS
  reports label their value column `"Results"` and pad headers
  (`"Analyte "`), which previously missed the long-format vocabulary and
  – when two or more numeric columns were present (result + detection
  limit + a numeric QC-lot id) – misclassified the table as wide,
  discarding the analyte column. This removes the need for the interim
  water-chemistry-qaqc guard.
