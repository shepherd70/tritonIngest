# Upgrade a legacy mapping profile without overwriting it

Upgrade a legacy mapping profile without overwriting it

## Usage

``` r
upgrade_mapping_profile(
  name_or_path,
  contracts,
  source_cols,
  dir = getOption("tritonIngest.profiles_dir"),
  output_name = NULL
)
```

## Arguments

- name_or_path:

  Legacy profile name/path.

- contracts, source_cols:

  Current named role lists.

- dir:

  Profiles directory.

- output_name:

  Name for the new v2 profile.

## Value

New v2 profile path, invisibly.
