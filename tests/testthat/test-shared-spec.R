test_that("shared diagnostics use the pinned external registry", {
  root <- Sys.getenv("TABULAR_INGESTION_SPEC_DIR")
  skip_if(!nzchar(root), "Set TABULAR_INGESTION_SPEC_DIR for shared conformance")
  expect_equal(trimws(readLines(file.path(root, "VERSION"), warn = FALSE)),
               "1.0.0-rc.1")
  registry <- jsonlite::fromJSON(file.path(root, "diagnostic-codes.json"))
  expect_true("duplicate_header" %in% registry$codes$code)
  diag <- tabular_diagnostic("duplicate_header", "warning", "structure",
                             message = "Duplicate header requires review.")
  expect_true(diag$code %in% registry$codes$code)
})
