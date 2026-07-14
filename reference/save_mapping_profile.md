# Save a contract/header-bound mapping profile

Save a contract/header-bound mapping profile

## Usage

``` r
save_mapping_profile(
  name,
  mappings,
  contracts,
  source_cols,
  meta = NULL,
  dir = getOption("tritonIngest.profiles_dir"),
  overwrite = TRUE
)
```

## Arguments

- name:

  Human-readable profile name.

- mappings:

  Named role -\> field/source mapping list.

- contracts:

  Named role -\> contract list.

- source_cols:

  Named role -\> ordered source header list.

- meta:

  Additional provenance.

- dir:

  Profiles directory.

- overwrite:

  Permit replacing the same profile name.

## Value

Written path, invisibly.
