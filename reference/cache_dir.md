# Resolve (and optionally create) the cache directory.

Resolve (and optionally create) the cache directory.

## Usage

``` r
cache_dir(dir = getOption("tritonIngest.cache_dir"), create = TRUE)
```

## Arguments

- dir:

  Directory to store cache files in. Defaults to
  `getOption("tritonIngest.cache_dir")`; errors if neither is set.

- create:

  Logical; create the directory if it does not exist.

## Value

Absolute path to the cache directory.
