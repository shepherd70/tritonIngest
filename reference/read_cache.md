# Read from the materialisation cache, if present and still fresh.

Returns the cached object when the data file and its sidecar exist and –
when the sidecar recorded a source fingerprint – the current `source`
still matches it. A miss or a stale/changed source returns `NULL` (with
a message), so the caller re-parses rather than trusting an out-of-date
cache.

## Usage

``` r
read_cache(
  key = NULL,
  source = NULL,
  dir = getOption("tritonIngest.cache_dir"),
  format = c("rds", "parquet")
)
```

## Arguments

- key:

  Cache key. Defaults to one derived from `source`.

- source:

  Path(s) to the current source file(s); compared against the recorded
  fingerprint. `NULL` skips the freshness check.

- dir:

  Cache directory (see
  [`cache_dir()`](https://shepherd70.github.io/tritonIngest/reference/cache_dir.md)).

- format:

  `"rds"` (default) or `"parquet"`.

## Value

The cached object, or `NULL` on a miss / stale source.
