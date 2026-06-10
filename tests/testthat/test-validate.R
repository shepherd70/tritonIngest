# Tests for the generic validation kernel (validate.R)

df_ok <- tibble::tibble(
  reach_id = c("R1", "R2"),
  date     = as.Date(c("2026-06-01", "2026-06-02")),
  count    = c(3L, 5L),
  effort   = c(120.5, 98.2)
)

test_that("check_required_columns passes when all columns present", {
  expect_identical(
    check_required_columns(df_ok, c("reach_id", "date"), "tbl"),
    character(0)
  )
})

test_that("check_required_columns accepts a named type-spec vector", {
  spec <- c(reach_id = "character", missing_col = "numeric")
  out <- check_required_columns(df_ok, spec, "tbl")
  expect_length(out, 1)
  expect_match(out, "missing required column\\(s\\): missing_col")
})

test_that("check_required_columns lists all missing columns in one message", {
  out <- check_required_columns(df_ok, c("a", "reach_id", "b"), "tbl")
  expect_length(out, 1)
  expect_match(out, "a, b")
})

test_that("check_column_types passes on conforming columns", {
  spec <- c(reach_id = "character", date = "Date", count = "integer", effort = "numeric")
  expect_identical(check_column_types(df_ok, spec, "tbl"), character(0))
})

test_that("check_column_types reports each mismatched column", {
  spec <- c(reach_id = "integer", count = "character")
  out <- check_column_types(df_ok, spec, "tbl")
  expect_length(out, 2)
  expect_match(out[1], "tbl\\$reach_id should be integer, found character")
  expect_match(out[2], "tbl\\$count should be character, found integer")
})

test_that("check_column_types skips absent columns", {
  expect_identical(
    check_column_types(df_ok, c(not_here = "numeric"), "tbl"),
    character(0)
  )
})

test_that("type_matches semantics", {
  expect_true(type_matches("integer", "numeric"))   # numeric is permissive
  expect_true(type_matches("double", "numeric"))
  expect_false(type_matches("numeric", "integer"))  # integer is strict
  expect_true(type_matches("Date", "Date"))
  expect_true(type_matches("Date", "date"))         # contract-style lowercase
  expect_false(type_matches("character", "Date"))
  expect_true(type_matches("logical", "logical"))
  expect_true(type_matches("factor", "factor"))     # exact-match fallback
})

test_that("check_no_na passes on complete columns and skips absent ones", {
  expect_identical(check_no_na(df_ok, c("reach_id", "ghost"), "tbl"), character(0))
})

test_that("check_no_na counts NAs per column", {
  df <- tibble::tibble(a = c(1, NA, NA), b = c("x", NA, "z"), c = 1:3)
  out <- check_no_na(df, c("a", "b", "c"), "tbl")
  expect_length(out, 2)
  expect_match(out[1], "tbl\\$a contains 2 NA value\\(s\\)")
  expect_match(out[2], "tbl\\$b contains 1 NA value\\(s\\)")
})

test_that("validation_abort is silent on empty failures", {
  expect_invisible(validation_abort(character(0)))
  expect_true(validation_abort(character(0)))
})

test_that("validation_abort signals a classed error carrying all failures", {
  failures <- c("first problem", "second problem")
  err <- tryCatch(
    validation_abort(failures, class = "cpue_validation_error"),
    error = function(e) e
  )
  expect_s3_class(err, "cpue_validation_error")
  expect_s3_class(err, "triton_validation_error")
  expect_identical(err$failures, failures)
  expect_match(conditionMessage(err), "2 issue\\(s\\)")
  expect_match(conditionMessage(err), "first problem")
  expect_match(conditionMessage(err), "second problem")
})

test_that("validation_abort honours a custom header", {
  err <- tryCatch(
    validation_abort("oops", header = "Custom header:"),
    error = function(e) e
  )
  expect_match(conditionMessage(err), "^Custom header:")
})
