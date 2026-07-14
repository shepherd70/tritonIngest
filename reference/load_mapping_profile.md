# Load and validate a mapping profile

`triton-mapping-profile/v2` profiles require current contracts and
ordered source headers. Legacy v1 profiles are rejected unless
`allow_legacy = TRUE`; they remain unvalidated and should only be passed
to
[`upgrade_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/upgrade_mapping_profile.md).

## Usage

``` r
load_mapping_profile(
  name_or_path,
  contracts = NULL,
  source_cols = NULL,
  dir = getOption("tritonIngest.profiles_dir"),
  allow_legacy = FALSE
)
```

## Arguments

- name_or_path:

  Profile name or JSON path.

- contracts, source_cols:

  Current named role lists.

- dir:

  Profiles directory.

- allow_legacy:

  Explicitly inspect a v1 profile.

## Value

Validated profile list.
