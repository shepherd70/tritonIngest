# Load a mapping profile from disk.

Accepts either a profile name (resolved against `dir`) or a direct path
to a `.json` file.

## Usage

``` r
load_mapping_profile(
  name_or_path,
  dir = getOption("tritonIngest.profiles_dir")
)
```

## Arguments

- name_or_path:

  Profile name or path to a profile JSON file.

- dir:

  Profiles directory (see
  [`mapping_profiles_dir()`](https://shepherd70.github.io/tritonIngest/reference/mapping_profiles_dir.md)).

## Value

A list with `name`, `mappings`, `meta`, `saved_at`. Each role's mapping
is a named character vector (contract field -\> source column).
