# Read a fresh, verified cache entry

Read a fresh, verified cache entry

## Usage

``` r
read_cache(
  key = NULL,
  source = NULL,
  dir = getOption("tritonIngest.cache_dir"),
  format = c("rds", "parquet"),
  transform_context = NULL
)
```

## Arguments

- key:

  Cache key, derived from `source` when omitted.

- source:

  Current source path(s).

- dir:

  Cache directory.

- format:

  `"rds"` or `"parquet"`.

- transform_context:

  Transformation identity used when the entry was written.

## Value

Cached object or `NULL` on any miss/mismatch.
