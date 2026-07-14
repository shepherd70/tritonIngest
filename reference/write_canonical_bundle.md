# Write a verified canonical interchange bundle

Write a verified canonical interchange bundle

## Usage

``` r
write_canonical_bundle(
  x,
  dir,
  name,
  sources,
  contract,
  diagnostics = list(),
  transform_context,
  format = c("parquet", "feather")
)
```

## Arguments

- x:

  Data frame to write.

- dir:

  Output directory.

- name:

  Artifact stem.

- sources:

  Source file path(s).

- contract:

  Contract describing the canonical table.

- diagnostics:

  List of
  [`tabular_diagnostic()`](https://shepherd70.github.io/tritonIngest/reference/tabular_diagnostic.md)
  objects.

- transform_context:

  Named transformation identity; see
  [`cached_ingest()`](https://shepherd70.github.io/tritonIngest/reference/cached_ingest.md).

- format:

  `"parquet"` (default) or `"feather"`.

## Value

Manifest path, invisibly.
