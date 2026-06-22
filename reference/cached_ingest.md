# Ingest a source, using the cache when fresh and rebuilding it when not.

The standard ingest-with-cache flow: try
[`read_cache()`](https://shepherd70.github.io/tritonIngest/reference/read_cache.md);
on a miss/stale source, run `parse(source, ...)`, write the result to
the cache, and return it. `parse` defaults to
[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
but is typically a project-specific function that parses *and* validates
into the canonical object.

## Usage

``` r
cached_ingest(
  source,
  parse = read_tabular,
  key = NULL,
  dir = getOption("tritonIngest.cache_dir"),
  format = c("rds", "parquet"),
  fingerprint = c("md5", "size_mtime"),
  ...
)
```

## Arguments

- source:

  Path(s) to the source file(s).

- parse:

  Function called as `parse(source, ...)` on a cache miss; must return
  the object to cache. Defaults to
  [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md).

- key:

  Cache key. Defaults to one derived from `source`.

- dir:

  Cache directory (see
  [`cache_dir()`](https://shepherd70.github.io/tritonIngest/reference/cache_dir.md)).

- format:

  `"rds"` (default) or `"parquet"`.

- fingerprint:

  Source-fingerprint method (see
  [`write_cache()`](https://shepherd70.github.io/tritonIngest/reference/write_cache.md)).

- ...:

  Passed to `parse`.

## Value

The canonical object, from cache or freshly parsed.
