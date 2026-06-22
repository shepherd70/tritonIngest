# Delete a mapping profile.

Delete a mapping profile.

## Usage

``` r
delete_mapping_profile(
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

`TRUE` if a file was removed, `FALSE` if none existed.
