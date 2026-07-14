# A header-less, all-text frame with junk above, within, and around the data:
# a title row, a blank row, the real header on row 3, an interspersed blank row,
# a trailing blank row, a fully-blank spacer column (d), and stray whitespace.
messy <- tibble::tibble(
  a = c("Spawner Survey 2025", "", "site", "A ", "", "B", ""),
  b = c("",                    "", "length_mm", "350", "", "420", ""),
  c = c("",                    "", "count", "2", "", "1", ""),
  d = c("",                    "", "", "", "", "", ""),
  e = c("",                    "", "comment", "ok", "", "", "")
)

test_that("drop_blank_rows / drop_blank_cols remove all-blank lines", {
  df <- tibble::tibble(a = c("x", "", "y"), b = c("1", "", "2"), c = c("", "", ""))
  expect_equal(nrow(drop_blank_rows(df)), 2)        # the all-blank middle row goes
  expect_equal(names(drop_blank_cols(df)), c("a", "b"))  # the all-blank c column goes
})

test_that("find_header_row skips blank and sparse title rows", {
  expect_equal(find_header_row(messy), 3L)
  df <- tibble::tibble(a = c("Title", "", "site", "A", "B"),
                       b = c("",      "", "len",  "350", "420"))
  expect_equal(find_header_row(df), 3L)
})

test_that("find_header_row returns NA when no header is convincing", {
  allnum <- tibble::tibble(a = c("1", "2", "3"), b = c("4", "5", "6"))
  expect_true(is.na(find_header_row(allnum)))
})

test_that("clean_table promotes the header and strips junk", {
  out <- clean_table(messy)
  expect_s3_class(out, "tbl_df")
  expect_equal(names(out), c("site", "length_mm", "count", "comment"))  # d dropped
  expect_equal(nrow(out), 2)                       # title/blank/blank rows gone
  expect_equal(out$site, c("A", "B"))              # leading "A " trimmed
  expect_equal(out$length_mm, c("350", "420"))
  expect_type(out$length_mm, "character")          # all-text contract preserved
  expect_equal(out$comment, c("ok", ""))
})

test_that("clean_table is a no-op on already-clean input (header on row 1)", {
  clean_in <- tibble::tibble(a = c("site", "A", "B"), b = c("count", "2", "1"))
  out <- clean_table(clean_in)
  expect_equal(names(out), c("site", "count"))
  expect_equal(out$site, c("A", "B"))
  expect_equal(out$count, c("2", "1"))
})

test_that("clean_table fails closed unless header repair is requested", {
  dup <- tibble::tibble(a = c("site", "A", "B"),
                        b = c("site", "x", "y"))
  expect_error(suppressWarnings(clean_table(dup)), "duplicate promoted header")
  expect_warning(out <- clean_table(dup, duplicate_names = "warn"),
                 "duplicate promoted header")
  expect_equal(names(out), c("site", "site_1"))
  expect_equal(nrow(out), 2)
  repaired <- suppressWarnings(clean_table(dup, duplicate_names = "repair"))
  diag <- attr(repaired, "diagnostics")[[1]]
  expect_equal(diag$details$repairs[[2]]$repaired, "site_1")
  expect_true(diag$requires_review)
  blank <- tibble::tibble(a = c("site", "A"), b = c("", "9"))
  expect_warning(clean_table(blank, header_row = 1),
                 "header cell\\(s\\) blank over populated column")
  # a blank header over a blank column is normal spacer padding and stays silent
  pad <- tibble::tibble(a = c("site", "A"), b = c("count", "2"), c = c("", ""))
  expect_silent(out <- clean_table(pad))
  expect_equal(names(out), c("site", "count"))   # the spacer column is dropped
})

test_that("clean_table reconstructs a multi-row header (RC7)", {
  # readxl leaves a merged group label only in its top-left cell
  multi <- tibble::tibble(
    a = c("Date", "",           "45521", "45522"),
    b = c("EPH",  "C10-C19",    "<0.25", "0.3"),
    c = c("",     "C19-C32",    "<0.25", "0.4")
  )
  out <- clean_table(multi, header_rows = 1:2)
  expect_equal(names(out), c("Date", "EPH C10-C19", "C19-C32"))
  expect_equal(nrow(out), 2)
  expect_equal(out[["EPH C10-C19"]], c("<0.25", "0.3"))
  expect_error(clean_table(multi, header_rows = c(1, 99)), "out of range")
})

test_that("drop_label_rows removes section dividers and footnote banners (RC7)", {
  df <- tibble::tibble(
    a = c("Physical Tests", "TSS", "Notes:",  "pH"),
    b = c("",               "mg/L", "",       "-"),
    c = c("",               "3.0",  "",       "7.2")
  )
  out <- drop_label_rows(df)
  expect_equal(nrow(out), 2)
  expect_equal(out$a, c("TSS", "pH"))
  # clean_table can do it in one pass
  grid <- tibble::tibble(a = c("analyte", "Physical Tests", "TSS"),
                         b = c("value",   "",               "3.0"))
  expect_equal(nrow(clean_table(grid, drop_labels = TRUE)), 1)
  expect_equal(nrow(clean_table(grid, drop_labels = FALSE)), 2)
})

test_that("clean_table still keeps a populated metadata row (documented limit)", {
  # the "Permit limit" row is not blank and not a label row: it survives on purpose
  grid <- tibble::tibble(a = c("Date", "Permit limit", "45521"),
                         b = c("TSS",  "75",           "3.0"))
  out <- clean_table(grid, drop_labels = TRUE)
  expect_equal(names(out), c("Date", "TSS"))
  expect_equal(nrow(out), 2)
  expect_equal(out$Date[1], "Permit limit")
  # the only signal is coerce_excel_date() refusing the string; check_not_metadata_row
  # would be the real fix and does not exist. Recorded here so the gap is visible.
  expect_warning(d <- coerce_excel_date(out$Date), "neither an Excel serial")
  expect_true(is.na(d[1]))
})

test_that("clean_table honours an explicit header_row and errors out of range", {
  out <- clean_table(messy, header_row = 3)
  expect_equal(names(out), c("site", "length_mm", "count", "comment"))
  expect_error(clean_table(messy, header_row = 99), "out of range")
})

test_that("clean_table warns and falls back when no header is detected", {
  allnum <- tibble::tibble(a = c("1", "2", "3"), b = c("4", "5", "6"))
  expect_warning(out <- clean_table(allnum), "could not detect a header")
  expect_equal(names(out), c("1", "4"))            # first row used as header
  expect_equal(nrow(out), 2)
})

test_that("read_tabular(col_names = FALSE) keeps every row as text for cleaning", {
  tmp <- tempfile(fileext = ".csv"); on.exit(unlink(tmp))
  writeLines(c("Spawner Survey,", "site,count", "A,2", "B,3"), tmp)
  raw <- read_tabular(tmp, col_names = FALSE)
  expect_equal(nrow(raw), 4)
  expect_type(raw[[1]], "character")
  tidy <- clean_table(raw)
  expect_equal(names(tidy), c("site", "count"))
  expect_equal(tidy$site, c("A", "B"))
})
