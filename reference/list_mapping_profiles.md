# List saved mapping profiles.

List saved mapping profiles.

## Usage

``` r
list_mapping_profiles(dir = getOption("tritonIngest.profiles_dir"))
```

## Arguments

- dir:

  Profiles directory (see
  [`mapping_profiles_dir()`](https://shepherd70.github.io/tritonIngest/reference/mapping_profiles_dir.md)).

## Value

A tibble with `name`, `file`, and `modified` (POSIXct), newest first;
zero rows if none exist.
