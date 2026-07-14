test_that("tabular diagnostics have stable structured fields", {
  d <- tabular_diagnostic("duplicate_header", "warning", "read",
                          message = "Duplicate source headers", source_rows = 1,
                          requires_review = TRUE)
  expect_equal(names(d), c("schema", "code", "severity", "stage", "message",
                           "requires_review", "table", "sheet", "column",
                           "source_rows", "cells", "details"))
  expect_true(d$requires_review)
  expect_error(tabular_diagnostic("x", "warning", "read", message = ""), "message")
})
