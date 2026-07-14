# Ingest a source using a verified cache

Custom parsers must supply `transform_context` with `parser_id`,
`parser_version`, and `schema_version`. The context and `...` arguments
are fingerprinted so a changed sheet, contract, profile, or parser
configuration cannot reuse an obsolete object.

## Usage

``` r
cached_ingest(
  source,
  parse = read_tabular,
  key = NULL,
  dir = getOption("tritonIngest.cache_dir"),
  format = c("rds", "parquet"),
  fingerprint = c("md5", "size_mtime"),
  transform_context = NULL,
  ...
)
```

## Arguments

- source:

  Source path(s).

- parse:

  Parser called as `parse(source, ...)`.

- key, dir, format, fingerprint:

  Cache settings.

- transform_context:

  Required for custom parsers; automatically generated for
  [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md).

- ...:

  Parser arguments included in the transformation fingerprint.

## Value

Cached or freshly parsed object.
