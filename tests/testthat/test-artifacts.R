test_that("canonical bundles round-trip and verify identity", {
  skip_if_not_installed("arrow")
  source <- tempfile(fileext = ".csv")
  writeLines(c("site,value", "A,1"), source)
  dir <- tempfile("bundle_")
  ct <- as_contract(list(cf_field("site", required = TRUE),
                         cf_field("value", "numeric", required = TRUE)))
  diagnostics <- tabular_diagnostic("validation_failed", "warning", "validation",
                                    message = "Example review finding")
  manifest <- write_canonical_bundle(
    data.frame(site = "A", value = 1), dir, "sample", source, ct, diagnostics,
    transform_context = list(parser_id = "test", parser_version = "1",
                             schema_version = "test/v1"))
  expect_true(file.exists(manifest))
  bundle <- read_canonical_bundle(manifest)
  expect_equal(as.data.frame(bundle$data), data.frame(site = "A", value = 1))
  expect_equal(bundle$manifest$schema, "tabular-artifact/v1")
  tampered <- bundle$manifest
  tampered$artifacts[[1]]$sha256 <- paste(rep("0", 64), collapse = "")
  jsonlite::write_json(tampered, manifest, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", na = "null")
  expect_error(read_canonical_bundle(manifest), "checksum")
})
