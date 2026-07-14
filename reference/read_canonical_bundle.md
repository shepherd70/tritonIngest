# Read and verify a canonical interchange bundle

Read and verify a canonical interchange bundle

## Usage

``` r
read_canonical_bundle(manifest, verify = TRUE)
```

## Arguments

- manifest:

  Path to a `tabular-artifact/v1` manifest.

- verify:

  Verify artifact and source hashes before reading.

## Value

A list with `data`, `manifest`, and `diagnostics`.
