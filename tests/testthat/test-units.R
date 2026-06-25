test_that("convert_units walks the concentration ladder", {
  expect_equal(convert_units(1, "mg/L", "ug/L"), 1000)
  expect_equal(convert_units(1000, "ug/L", "mg/L"), 1)
  expect_equal(convert_units(5, "mg/L", "mg/L"), 5)       # identity
})

test_that("convert_units is case/space-insensitive and NA on mismatch", {
  expect_equal(convert_units(1, "MG/L", "ug/l"), 1000)
  expect_warning(out <- convert_units(1, "meq/L", "mg/L"), "cannot convert")
  expect_true(is.na(out))                                 # not convertible
})

test_that("convert_units recycles `from` over the value vector", {
  out <- convert_units(c(1, 2), c("mg/L", "ug/L"), "ug/L")
  expect_equal(out, c(1000, 2))
})

test_that("convert_units walks the mass/mass ladder", {
  expect_equal(convert_units(1, "g/kg", "mg/kg"), 1000)
  expect_equal(convert_units(1, "mg/kg", "ug/g"), 1)      # 1 mg/kg == 1 ug/g (ppm)
  expect_equal(convert_units(1, "ng/g", "ug/kg"), 1)      # 1 ng/g == 1 ug/kg (ppb)
})

test_that("convert_units keeps mass/volume and mass/mass separate", {
  expect_warning(out <- convert_units(1, "mg/L", "mg/kg"), "incompatible")
  expect_true(is.na(out))                                 # no density => not convertible
})

test_that("convert_units folds Greek mu onto the micro sign", {
  micro <- paste0(intToUtf8(0x00B5), "g/L")   # U+00B5 MICRO SIGN
  greek <- paste0(intToUtf8(0x03BC), "g/L")   # U+03BC GREEK SMALL LETTER MU
  expect_equal(convert_units(1000, micro, "mg/L"), 1)
  expect_equal(convert_units(1000, greek, "mg/L"), 1)     # same result via Greek mu
})
