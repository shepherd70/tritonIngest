test_that("read_tabular reads CSV as all-text by default", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c("site,value", "A,<0.01", "B,007"), tmp)
  df <- read_tabular(tmp)
  expect_s3_class(df, "tbl_df")
  expect_type(df$value, "character")     # text preserved
  expect_equal(df$value, c("<0.01", "007"))
})

test_that("read_tabular errors on a missing file and unsupported type", {
  expect_error(read_tabular("does-not-exist.csv"), "File not found")
  tmp <- tempfile(fileext = ".dat"); file.create(tmp); on.exit(unlink(tmp))
  expect_error(read_tabular(tmp), "Unsupported file type")
})

test_that("coerce_excel_date handles serial / ISO / NA mixes", {
  d <- coerce_excel_date(c("45909", "2023-08-22", NA))
  expect_s3_class(d, "Date")
  expect_equal(d[2], as.Date("2023-08-22"))
  expect_true(is.na(d[3]))
  # serial 45909 in the 1900 system is 2025-09-05
  expect_equal(d[1], as.Date("1899-12-30") + 45909)
  # numeric input works too
  expect_equal(coerce_excel_date(c(45847, 45909)),
               as.Date("1899-12-30") + c(45847, 45909))
})
