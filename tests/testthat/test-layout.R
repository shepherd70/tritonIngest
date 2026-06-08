test_that("is_value_like recognises numbers and non-detect notation", {
  expect_true(is_value_like(c("1.2", "3.4", "<0.01", "ND")))
  expect_false(is_value_like(c("apple", "banana", "cherry")))
  expect_false(is_value_like(character(0)))
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
