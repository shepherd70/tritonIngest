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
  bundle <- read_canonical_bundle(manifest, sources = source)
  expect_equal(as.data.frame(bundle$data), data.frame(site = "A", value = 1))
  expect_equal(bundle$manifest$schema, "tabular-artifact/v1")
  expect_equal(bundle$verification$artifact$status, "verified")
  expect_equal(bundle$verification$sources$status, "verified")

  without_source <- read_canonical_bundle(manifest)
  expect_equal(without_source$verification$sources$status, "skipped")

  writeLines(c("site,value", "B,2"), source)
  expect_error(read_canonical_bundle(manifest, sources = source),
               "source checksum mismatch")
  writeLines(c("site,value", "A,1"), source)

  tampered <- bundle$manifest
  tampered$artifacts[[1]]$sha256 <- paste(rep("0", 64), collapse = "")
  jsonlite::write_json(tampered, manifest, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", na = "null")
  expect_error(read_canonical_bundle(manifest), "checksum")
})

test_that("canonical bundles inherit ingestion diagnostics by default", {
  skip_if_not_installed("arrow")
  source <- tempfile(fileext = ".csv")
  writeLines(c("site", "A"), source)
  x <- data.frame(site = "A")
  attr(x, "diagnostics") <- list(tabular_diagnostic(
    "formula_present", "info", "intake", "Formula provenance requires review",
    requires_review = TRUE))
  ct <- as_contract(list(cf_field("site")))
  manifest <- write_canonical_bundle(
    x, tempfile("bundle_"), "sample", source, ct,
    transform_context = list(parser_id = "test", parser_version = "1",
                             schema_version = "test/v1"))
  bundle <- read_canonical_bundle(manifest)
  expect_equal(bundle$diagnostics[[1]]$code, "formula_present")
  expect_equal(bundle$manifest$diagnostics$summary$info, 1)
})

test_that("verify FALSE reports artifact and source checks as skipped", {
  skip_if_not_installed("arrow")
  source <- tempfile(fileext = ".csv")
  writeLines(c("site", "A"), source)
  manifest <- write_canonical_bundle(
    data.frame(site = "A"), tempfile("bundle_"), "sample", source,
    as_contract(list(cf_field("site"))),
    transform_context = list(parser_id = "test", parser_version = "1",
                             schema_version = "test/v1"))
  bundle <- read_canonical_bundle(manifest, verify = FALSE, sources = source)
  expect_equal(bundle$verification$artifact$status, "skipped")
  expect_equal(bundle$verification$sources$status, "skipped")
})
