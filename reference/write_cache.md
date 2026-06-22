# Write a parsed object to the materialisation cache.

Writes the data file plus a JSON sidecar recording the source
fingerprint, format, timestamp and shape, so
[`read_cache()`](https://shepherd70.github.io/tritonIngest/reference/read_cache.md)
can later decide whether the cache is still fresh.

## Usage

``` r
write_cache(
  x,
  source = NULL,
  key = NULL,
  dir = getOption("tritonIngest.cache_dir"),
  format = c("rds", "parquet"),
  fingerprint = c("md5", "size_mtime"),
  meta = list()
)
```

## Arguments

- x:

  The object to cache. For `format = "parquet"` it must be a data frame;
  any classes/attributes beyond the plain table are dropped (with a
  warning) — use `"rds"` to preserve a classed object exactly.

- source:

  Path(s) to the source file(s) the object was parsed from. Used to
  fingerprint the inputs; may be `NULL` to cache without invalidation.

- key:

  Cache key (file stem). Defaults to one derived from `source`.

- dir:

  Cache directory (see
  [`cache_dir()`](https://shepherd70.github.io/tritonIngest/reference/cache_dir.md)).

- format:

  `"rds"` (default) or `"parquet"`.

- fingerprint:

  Source-fingerprint method, `"md5"` (default) or `"size_mtime"`
  (cheaper for very large sources).

- meta:

  Optional named list of extra provenance to record in the sidecar.

## Value

The path to the written data file (invisibly).
