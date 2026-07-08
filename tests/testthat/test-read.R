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

test_that("coerce_excel_date parses year-first slash dates and respects origin", {
  expect_equal(coerce_excel_date("2023/08/22"), as.Date("2023-08-22"))
  # the same serial under the 1904 system lands later than under the 1900 default
  d1900 <- coerce_excel_date(1000)
  d1904 <- coerce_excel_date(1000, origin = "1904-01-01")
  expect_equal(as.numeric(d1904 - d1900),
               as.numeric(as.Date("1904-01-01") - as.Date("1899-12-30")))
})

test_that("coerce_excel_date warns on values matching neither serial nor format", {
  expect_warning(d <- coerce_excel_date(c("2023-08-22", "not-a-date")),
                 "neither an Excel serial nor a known date format")
  expect_equal(d[1], as.Date("2023-08-22"))
  expect_true(is.na(d[2]))
})

test_that("coerce_excel_date can exclude year-like integers via serial_range", {
  # tightened range: a bare 4-digit year is no longer misread as a serial
  expect_warning(d <- coerce_excel_date("2024", serial_range = c(10000, 60000)),
                 "neither an Excel serial")
  expect_true(is.na(d))
  # the full default range still treats it as a serial, but now says so
  expect_warning(d2 <- coerce_excel_date("2024"), "treated as Excel serials")
  expect_s3_class(d2, "Date")
  # a real serial well outside the year band stays silent
  expect_silent(coerce_excel_date("45909"))
})

test_that("coerce_excel_date does not prefix-match a day-first date (RC3)", {
  # as.Date("18-08-2024", "%Y-%m-%d") consumes %Y="18" and DISCARDS the trailing
  # "24", returning 0018-08-20 with no warning. strict = TRUE must refuse that.
  expect_equal(as.Date("18-08-2024", format = "%Y-%m-%d"), as.Date("0018-08-20"))

  expect_warning(d <- coerce_excel_date(c("18-08-2024", "09/10/2024")),
                 "neither an Excel serial")
  expect_true(all(is.na(d)))

  # with the right format they parse, and unambiguously
  expect_equal(coerce_excel_date("18-08-2024", formats = "%d-%m-%Y"),
               as.Date("2024-08-18"))

  # strict = FALSE restores the old, lenient (and wrong) behaviour
  expect_equal(coerce_excel_date("18-08-2024", strict = FALSE), as.Date("0018-08-20"))

  # year-first values still parse, and a trailing newline from a wrapped Excel
  # cell is trimmed rather than defeating the match
  expect_equal(coerce_excel_date("2024-08-18\n"), as.Date("2024-08-18"))
  expect_equal(coerce_excel_date("2024-8-1"), as.Date("2024-08-01"))
})

test_that("coerce_excel_date rejects an unsupported format code", {
  expect_error(coerce_excel_date("x", formats = "%Q"), "unsupported format code")
})

test_that("sniff_format identifies content, not the extension (RC2)", {
  csv <- tempfile(fileext = ".csv"); on.exit(unlink(csv), add = TRUE)
  writeLines(c("a,b", "1,2"), csv)
  expect_equal(sniff_format(csv), "text")

  empty <- tempfile(fileext = ".csv"); file.create(empty); on.exit(unlink(empty), add = TRUE)
  expect_equal(sniff_format(empty), "empty")

  # a real zip wearing a .csv name
  skip_if_not_installed("zip")
  zipped <- tempfile(fileext = ".csv"); on.exit(unlink(zipped), add = TRUE)
  inner <- tempfile(fileext = ".txt"); writeLines("hello", inner); on.exit(unlink(inner), add = TRUE)
  zip::zipr(zipped, inner)
  expect_equal(sniff_format(zipped), "zip")

  expect_error(read_tabular(zipped), "contents are a ZIP archive")
  expect_error(read_tabular(zipped), "format = \"xlsx\"")
})

test_that("read_tabular warns about duplicate source column names (RC6)", {
  tmp <- tempfile(fileext = ".csv"); on.exit(unlink(tmp))
  writeLines(c("site,zinc,zinc", "A,1,2"), tmp)
  expect_warning(df <- read_tabular(tmp), "duplicate column name")
  expect_warning(read_tabular(tmp), "at positions 2, 3")
  # the reader still repairs them; the point is that it no longer does so silently
  expect_equal(ncol(df), 3)
  # col_names = FALSE has no header to check
  expect_silent(read_tabular(tmp, col_names = FALSE))
})
