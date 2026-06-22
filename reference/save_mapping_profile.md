# Save a mapping profile to disk.

Save a mapping profile to disk.

## Usage

``` r
save_mapping_profile(
  name,
  mappings,
  meta = NULL,
  dir = getOption("tritonIngest.profiles_dir"),
  overwrite = TRUE
)
```

## Arguments

- name:

  Human-readable profile name (also used to derive the filename).

- mappings:

  A named list keyed by role; each element a named list/char vector of
  `contract field -> source column`.

- meta:

  Optional named list of provenance (e.g. source kind, sheet).

- dir:

  Profiles directory (see
  [`mapping_profiles_dir()`](https://shepherd70.github.io/tritonIngest/reference/mapping_profiles_dir.md)).

- overwrite:

  Logical; allow overwriting an existing same-named profile.

## Value

The path to the written JSON file (invisibly).
