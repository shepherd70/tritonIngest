# Row-level checks (RC8). The pre-0.6.0 kernel was column-level and count-only:
# it compared classes and counted NAs, but never looked at a record.

test_that("check_unique finds duplicate keys and names the rows", {
  d <- data.frame(date = c("45521", "45522", "45951", "45951"),
                  time = c("08:00", "09:00", "08:46", "08:46"),
                  stringsAsFactors = FALSE)
  msg <- check_unique(d, c("date", "time"), "clean")
  expect_length(msg, 1)
  expect_match(msg, "2 row\\(s\\) sharing 1 duplicated key")
  expect_match(msg, "at rows 3,4")

  uniq <- data.frame(a = 1:3, b = 4:6)
  expect_equal(check_unique(uniq, c("a", "b"), "t"), character(0))
  expect_equal(check_unique(uniq, "nope", "t"), character(0))     # absent col skipped
  expect_equal(check_unique(uniq[0, ], "a", "t"), character(0))   # zero rows
})

test_that("check_unique truncates a long offender list", {
  d <- data.frame(k = rep(letters[1:10], each = 2))
  msg <- check_unique(d, "k", "t", max_report = 3L)
  expect_match(msg, "20 row\\(s\\) sharing 10 duplicated key")
  expect_match(msg, "and 7 more")
})

test_that("check_range catches physically impossible values", {
  d <- data.frame(pH = c(7.2, 42.4, 6.8), survival = c(100, 150, 50))
  msgs <- check_range(d, list(pH = c(0, 14), survival = c(0, 100)), "calc")
  expect_length(msgs, 2)
  expect_match(msgs[1], "calc\\$pH has 1 value\\(s\\) outside \\[0, 14\\]")
  expect_match(msgs[1], "at row\\(s\\) 2")
  expect_match(msgs[2], "survival")

  # open-ended bounds, absent columns, empty spec
  expect_length(check_range(data.frame(x = c(-1, 2)), list(x = c(0, NA)), "t"), 1)
  expect_equal(check_range(d, list(missing_col = c(0, 1)), "t"), character(0))
  expect_equal(check_range(d, list(), "t"), character(0))
  expect_error(check_range(d, list(pH = 3), "t"), "must be c\\(min, max\\)")
  # NA values are not out-of-range
  expect_equal(check_range(data.frame(x = c(NA, 5)), list(x = c(0, 10)), "t"), character(0))
})

test_that("check_monotonic finds the backwards step a range check cannot", {
  # serial 45951 sits between 45583 and 45588: a valid date, in the wrong order
  d <- data.frame(date = c(45583, 45951, 45588, 45591))
  msgs <- check_monotonic(d, "date", "clean")
  expect_length(msgs, 1)
  expect_match(msgs, "not non-decreasing: 1 backwards step")
  expect_match(msgs, "at row\\(s\\) 3")

  expect_equal(check_monotonic(data.frame(d = 1:5), "d", "t"), character(0))
  expect_equal(check_monotonic(data.frame(d = 1:5), "absent", "t"), character(0))
  expect_equal(check_monotonic(data.frame(d = c(1, NA)), "d", "t"), character(0))
  expect_length(check_monotonic(data.frame(d = 5:1), "d", "t", increasing = FALSE), 0)

  # gap detection catches the same defect from the other side
  gaps <- check_monotonic(data.frame(date = c(45583, 45951)), "date", "clean",
                          max_gap = 300)
  expect_match(gaps, "step\\(s\\) larger than 300")

  # works on Date columns too
  dd <- data.frame(date = as.Date(c("2024-10-18", "2025-10-21", "2024-10-23")))
  expect_match(check_monotonic(dd, "date", "clean"), "backwards step")
})

test_that("the new checks compose with validation_abort", {
  d <- data.frame(pH = c(7.2, 42.4), site = c("A", "A"))
  failures <- c(check_range(d, list(pH = c(0, 14)), "d"),
                check_unique(d, "site", "d"))
  expect_length(failures, 2)
  expect_error(validation_abort(failures), "Input validation failed with 2 issue")
  expect_true(inherits(
    tryCatch(validation_abort(failures), error = function(e) e),
    "triton_validation_error"))
})
