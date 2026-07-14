# Read and verify a canonical interchange bundle

Read and verify a canonical interchange bundle

## Usage

``` r
read_canonical_bundle(manifest, verify = TRUE, sources = NULL)
```

## Arguments

- manifest:

  Path to a `tabular-artifact/v1` manifest.

- verify:

  Verify bundle-contained artifact checksums before reading. When
  `sources` is supplied, also verify current source identity.

- sources:

  Optional current source path(s), in manifest order. With
  `verify = TRUE`, basename, byte size, content signature, and SHA-256
  must match the manifest. When omitted, source verification is
  explicitly reported as skipped in the returned `verification` record.

## Value

A list with `data`, `manifest`, `diagnostics`, and `verification`.
