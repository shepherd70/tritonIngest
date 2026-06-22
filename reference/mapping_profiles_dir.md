# Resolve (and optionally create) the mapping-profiles directory.

Resolve (and optionally create) the mapping-profiles directory.

## Usage

``` r
mapping_profiles_dir(
  dir = getOption("tritonIngest.profiles_dir"),
  create = TRUE
)
```

## Arguments

- dir:

  Directory to store profiles in. Defaults to
  `getOption("tritonIngest.profiles_dir")`; errors if neither is set.

- create:

  Logical; create the directory if it does not exist.

## Value

Absolute path to the profiles directory.
