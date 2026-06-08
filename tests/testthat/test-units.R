test_that("convert_units walks the concentration ladder", {
  expect_equal(convert_units(1, "mg/L", "ug/L"), 1000)
  expect_equal(convert_units(1000, "ug/L", "mg/L"), 1)
  expect_equal(convert_units(5, "mg/L", "mg/L"), 5)       # identity
})

test_that("convert_units is case/space-insensitive and NA on mismatch", {
  expect_equal(convert_units(1, "MG/L", "ug/l"), 1000)
  expect_true(is.na(convert_units(1, "meq/L", "mg/L"))) # not convertible
})

test_that("convert_units recycles `from` over the value vector", {
  out <- convert_units(c(1, 2), c("mg/L", "ug/L"), "ug/L")
  expect_equal(out, c(1000, 2))
})
