# Write an object to the transformation-aware cache

Write an object to the transformation-aware cache

## Usage

``` r
write_cache(
  x,
  source = NULL,
  key = NULL,
  dir = getOption("tritonIngest.cache_dir"),
  format = c("rds", "parquet"),
  fingerprint = c("md5", "size_mtime"),
  meta = list(),
  transform_context = NULL
)
```

## Arguments

- x:

  Object to cache; parquet requires a data frame.

- source:

  Source file path(s), or `NULL` for a provenance-only artifact.

- key:

  Cache key; derived from `source` when omitted.

- dir:

  Cache directory.

- format:

  `"rds"` or `"parquet"`.

- fingerprint:

  `"md5"` or `"size_mtime"` source fingerprint.

- meta:

  Additional metadata.

- transform_context:

  Optional named transformation identity. Cache reads must supply the
  same context when one is recorded.

## Value

Data path, invisibly.
