test_that("is_value_like recognises numbers and non-detect notation", {
  expect_true(is_value_like(c("1.2", "3.4", "<0.01", "ND")))
  expect_false(is_value_like(c("apple", "banana", "cherry")))
  expect_false(is_value_like(character(0)))
})

test_that("is_value_like uses the shared non-detect vocabulary", {
  # "NON-DETECT"/"NONDETECT" live in ND_TOKENS (shared with parse_censored); the
  # layout side previously carried a shorter list and would have missed them.
  expect_true(is_value_like(c("1.2", "3.4", "NON-DETECT", "nondetect")))
})

test_that("is_value_like shares Unicode censor normalization with parsing", {
  le <- intToUtf8(0x2264)
  ge <- intToUtf8(0x2265)
  expect_true(is_value_like(c("1.2", paste0(le, "0.1"), paste0(ge, "670"))))
})

test_that("detect_layout finds long via parameter/value names", {
  df <- tibble::tibble(site = "A", parameter = "zinc", value = "1.2")
  d <- detect_layout(df)
  expect_equal(d$layout, "long")
})

test_that("detect_layout finds wide via multiple value-like columns", {
  df <- tibble::tibble(site = c("A", "B"),
                       zinc = c("1.2", "2.3"), copper = c("0.4", "0.5"))
  d <- detect_layout(df)
  expect_equal(d$layout, "wide")
  expect_setequal(d$value_like_cols, c("zinc", "copper"))
})

test_that("detect_layout recognises plural parameter/value column names", {
  df <- tibble::tibble(site = "A", Analytes = "zinc", Results = "1.2")
  expect_equal(detect_layout(df)$layout, "long")
})

test_that("detect_layout trims surrounding whitespace from column names", {
  # Lab exports routinely pad headers, e.g. "Analyte ".
  df <- tibble::tibble("parameter " = "zinc", " value" = "1.2")
  expect_equal(detect_layout(df)$layout, "long")
})

test_that("detect_layout reads a real ALS header as long, not wide", {
  # Regression for the ALS export that motivated the wq-side guard: the value
  # column is the plural "Results", the parameter header carries a trailing
  # space, and three numeric-ish columns (Results, Detection Limit, numeric
  # QC Lot id) would otherwise trip the >=2-value-like-columns wide heuristic.
  df <- tibble::tibble(
    "Analyte "         = c("Zinc", "Copper", "Lead"),
    "ALS Sample ID "   = c("VA26B0991-001", "VA26B0991-001", "VA26B0991-001"),
    "Client Sample ID" = c("KV-1", "KV-1", "KV-1"),
    "Matrix"           = c("Water", "Water", "Water"),
    "Method"           = c("EP200", "EP200", "EP200"),
    "Results"          = c("1.2", "0.4", "<0.5"),
    "Detection Limit"  = c("0.1", "0.1", "0.5"),
    "Units"            = c("mg/L", "mg/L", "mg/L"),
    "QC Lot"           = c("2580895", "2580895", "2580896")
  )
  d <- detect_layout(df)
  expect_equal(d$layout, "long")
  expect_match(d$reason, "parameter and value")
})

test_that("melt_wide reshapes analyte columns to long and drops empties", {
  df <- tibble::tibble(site = c("A", "B"),
                       zinc = c("1.2", ""), copper = c("0.4", "0.5"))
  long <- melt_wide(df, param_cols = c("zinc", "copper"))
  expect_equal(sort(names(long)), sort(c("site", "parameter", "value_raw", "units")))
  expect_equal(nrow(long), 3)                 # the empty zinc/B cell is dropped
  expect_true(all(c("zinc", "copper") %in% long$parameter))
  # units mapping
  long2 <- melt_wide(df, param_cols = "zinc", units = c(zinc = "mg/L"))
  expect_equal(unique(long2$units), "mg/L")
})

test_that("melt_wide errors on unknown param columns", {
  df <- tibble::tibble(site = "A", zinc = "1.2")
  expect_error(melt_wide(df, param_cols = "nope"), "not in data")
})

test_that("melt_wide refuses to clobber a reserved output column", {
  df <- tibble::tibble(units = "mg/L", zinc = "1.2", copper = "0.4")
  expect_error(melt_wide(df, param_cols = c("zinc", "copper")),
               "would overwrite existing column")
})
