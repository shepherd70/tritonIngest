# RC4 downstream + RC9. is_value_like() had to learn the same censored vocabulary
# parse_censored() knows, and detect_layout() had to learn that a numeric matrix
# with samples across the header is not a "wide" table.

test_that("is_value_like recognises right-censored and over-range tokens (RC4)", {
  expect_true(is_value_like(c("1.2", "3.4", ">2420", ">80")))
  expect_true(is_value_like(c("1.2", "TNTC")))
  # and a censor operator with no number is still not a value
  expect_false(is_value_like(c("<-", "<.", "<e")))
})

test_that("is_value_like ignores the '-' missing marker instead of failing on it (RC4)", {
  x <- c("7.8", "-", "-", "-", "7.2")          # 2 numbers, 3 placeholders
  expect_true(is_value_like(x))                # 0.4 numeric under the old rule
  expect_false(is_value_like(x, na_strings = character(0)))
  expect_false(is_value_like(c("-", "-")))     # nothing left to judge
})

test_that("detect_layout no longer loses analyte columns to '-' placeholders", {
  df <- tibble::tibble(
    Date  = c("45521", "45522", "45523"),
    TSS   = c("<3.0", "-", "4.5"),
    BOD5  = c("-", "<2.0", ">17.1"),
    COD   = c("-", "-", "<10")
  )
  d <- detect_layout(df)
  expect_equal(d$layout, "wide")
  expect_setequal(d$value_like_cols, c("TSS", "BOD5", "COD"))
})

test_that("melt_wide drops '-' placeholders as missing (RC4)", {
  df <- tibble::tibble(site = c("A", "B"), zinc = c("1.2", "-"), copper = c("-", "0.5"))
  long <- melt_wide(df, param_cols = c("zinc", "copper"))
  expect_equal(nrow(long), 2)
  expect_setequal(long$value_raw, c("1.2", "0.5"))
  expect_equal(nrow(melt_wide(df, param_cols = c("zinc", "copper"),
                              na_strings = character(0))), 4)
})

# --- RC9: transposed results matrices ---------------------------------------

test_that("looks_transposed spots an 'Analyte' label sitting in column 1", {
  m <- tibble::tibble(
    x1 = c("Sample Location", "LAB ID", "Analyte", "TSS", "Ammonia"),
    x2 = c("ETP Pond", "VA24C1052", "Units", "mg/L", "mg/L"),
    x3 = c("ETP Pond", "VA24C2556", "Effluent", "<3.0", "1.02")
  )
  r <- looks_transposed(m)
  expect_true(r$transposed)
  expect_match(r$reason, "appears as a CELL in column 1")
  expect_equal(detect_layout(m)$layout, "transposed")
})

test_that("looks_transposed spots duplicated sample headers over an analyte column", {
  m <- tibble::tibble(KV = c("TSS", "pH", "Zinc", "Copper", "Lead", "Iron"),
                      surface = c("1", "7.2", "3", "4", "5", "6"),
                      middle  = c("1", "7.3", "3", "4", "5", "6"))
  names(m) <- c("Site", "KV", "KV")             # duplicated header, minimal repair
  expect_true(looks_transposed(m)$transposed)
  expect_match(looks_transposed(m)$reason, "header names are duplicates")
})

test_that("looks_transposed does not fire on ordinary long or wide tables", {
  wide <- tibble::tibble(site = c("A", "B"), zinc = c("1.2", "2.3"),
                         copper = c("0.4", "0.5"))
  expect_false(looks_transposed(wide)$transposed)
  expect_equal(detect_layout(wide)$layout, "wide")

  long <- tibble::tibble(site = "A", parameter = "zinc", value = "1.2")
  expect_false(looks_transposed(long)$transposed)
  expect_equal(detect_layout(long)$layout, "long")

  # a long table whose first column holds analyte names, with unique headers
  als <- tibble::tibble(Analyte = c("Zinc", "Copper", "Lead", "Iron", "Nickel", "Tin"),
                        Results = c("1.2", "0.4", "<0.5", "3", "4", "5"),
                        Units   = rep("mg/L", 6))
  expect_false(looks_transposed(als)$transposed)
})

test_that("transpose_table reshapes an analyte-by-sample matrix into long form", {
  grid <- tibble::tibble(
    c1 = c("Sample Location", "LAB ID",    "Analyte", "TSS",  "Ammonia"),
    c2 = c(NA,                NA,          "Units",   "mg/L", "mg/L"),
    c3 = c("ETP Pond",        "VA24C1052", "Effluent", "<3.0", "1.02"),
    c4 = c("Basin 2",         "VA24C2556", "Effluent", "4.5",  "-")
  )
  long <- transpose_table(
    grid,
    header_rows = c(location = 1, lab_id = 2),
    body_rows   = 4:5,
    label_cols  = c(parameter = 1, units = 2),
    sample_cols = 3:4
  )
  expect_equal(nrow(long), 3)                       # the "-" cell is dropped
  expect_setequal(names(long), c("location", "lab_id", "parameter", "units", "value_raw"))
  expect_equal(long$parameter, c("TSS", "Ammonia", "TSS"))
  expect_equal(long$lab_id, c("VA24C1052", "VA24C1052", "VA24C2556"))
  expect_equal(long$value_raw, c("<3.0", "1.02", "4.5"))
  expect_equal(long$units, c("mg/L", "mg/L", "mg/L"))

  # the parsed result survives round-trip into parse_censored()
  p <- parse_censored(long$value_raw)
  expect_equal(p$censor_direction, c("left", "none", "none"))

  expect_error(transpose_table(grid, header_rows = c(1), body_rows = 4:5,
                               label_cols = c(parameter = 1), sample_cols = 3:4),
               "must be a \\*named\\* integer vector")
  expect_error(transpose_table(grid, header_rows = c(value_raw = 1), body_rows = 4:5,
                               label_cols = c(parameter = 1), sample_cols = 3:4),
               "reserved output name")
})
