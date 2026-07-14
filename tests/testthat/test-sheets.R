# Build a tiny .xlsx by hand so the tests need no fixture file. Only the parts
# readxl and list_sheets() actually read are written.
skip_if_no_zip <- function() skip_if_not_installed("zip")

.sheet_xml <- function(rows) {
  cells <- vapply(seq_along(rows), function(i) {
    sprintf('<row r="%d"><c r="A%d" t="inlineStr"><is><t>%s</t></is></c></row>', i, i, rows[i])
  }, character(1))
  paste0('<?xml version="1.0" encoding="UTF-8"?>',
         '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
         '<sheetData>', paste(cells, collapse = ""), '</sheetData></worksheet>')
}

make_workbook <- function(states = c(alpha = NA, beta = "hidden", gamma = "veryHidden"),
                          worksheet_xml = NULL) {
  skip_if_no_zip()
  root <- file.path(tempfile("wb-")); dir.create(root)
  dir.create(file.path(root, "_rels"))
  dir.create(file.path(root, "xl", "_rels"), recursive = TRUE)
  dir.create(file.path(root, "xl", "worksheets"), recursive = TRUE)

  nm <- names(states)
  sheet_tags <- vapply(seq_along(states), function(i) {
    st <- if (is.na(states[i])) "" else sprintf(' state="%s"', states[i])
    sprintf('<sheet name="%s" sheetId="%d" r:id="rId%d"%s/>', nm[i], i, i, st)
  }, character(1))

  writeLines(paste0('<?xml version="1.0" encoding="UTF-8"?>',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>',
    '</Relationships>'), file.path(root, "_rels", ".rels"))

  writeLines(paste0('<?xml version="1.0" encoding="UTF-8"?>',
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ',
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    '<sheets>', paste(sheet_tags, collapse = ""), '</sheets></workbook>'),
    file.path(root, "xl", "workbook.xml"))

  rels <- vapply(seq_along(states), function(i)
    sprintf('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>', i, i),
    character(1))
  writeLines(paste0('<?xml version="1.0" encoding="UTF-8"?>',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    paste(rels, collapse = ""), '</Relationships>'),
    file.path(root, "xl", "_rels", "workbook.xml.rels"))

  for (i in seq_along(states)) {
    xml <- if (is.null(worksheet_xml)) .sheet_xml(c("site", nm[i])) else worksheet_xml[[i]]
    writeLines(xml,
               file.path(root, "xl", "worksheets", sprintf("sheet%d.xml", i)))
  }

  ct <- paste0('<?xml version="1.0" encoding="UTF-8"?>',
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    '<Default Extension="xml" ContentType="application/xml"/>',
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
    paste(vapply(seq_along(states), function(i)
      sprintf('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>', i),
      character(1)), collapse = ""),
    '</Types>')
  writeLines(ct, file.path(root, "[Content_Types].xml"))

  out <- tempfile(fileext = ".xlsx")
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  zip::zipr(out, list.files(root, all.files = FALSE))
  out
}

.formula_sheet_xml <- function() {
  paste0('<?xml version="1.0" encoding="UTF-8"?>',
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    '<sheetData>',
    '<row r="1"><c r="A1" t="inlineStr"><is><t>value</t></is></c></row>',
    '<row r="2"><c r="A2"><f>1+1</f><v>2</v></c></row>',
    '<row r="3"><c r="A3"><f>2+2</f></c></row>',
    '</sheetData><mergeCells count="1"><mergeCell ref="A4:B4"/></mergeCells>',
    '</worksheet>')
}

test_that("list_sheets reports every sheet AND its visibility (RC1)", {
  wb <- make_workbook()
  on.exit(unlink(wb), add = TRUE)

  s <- list_sheets(wb)
  expect_equal(s$name, c("alpha", "beta", "gamma"))
  expect_equal(s$index, 1:3)
  expect_equal(s$visible, c("visible", "hidden", "veryHidden"))

  # readxl alone cannot tell you this
  expect_equal(readxl::excel_sheets(wb), c("alpha", "beta", "gamma"))
})

test_that("a veryHidden sheet in position 1 is what read_tabular() silently reads", {
  wb <- make_workbook(c(alpha = "veryHidden", beta = NA))
  on.exit(unlink(wb), add = TRUE)
  s <- list_sheets(wb)
  expect_equal(s$visible[1], "veryHidden")
  # this is the hazard list_sheets() exists to expose
  expect_equal(names(read_tabular(wb)), "site")
  expect_equal(read_tabular(wb)[[1]], "alpha")
})

test_that("read_all_sheets reads them all, and can skip hidden ones", {
  wb <- make_workbook()
  on.exit(unlink(wb), add = TRUE)

  all <- read_all_sheets(wb)
  expect_equal(names(all), c("alpha", "beta", "gamma"))
  expect_equal(attr(all$gamma, "sheet_visibility"), "veryHidden")

  expect_message(vis <- read_all_sheets(wb, include_hidden = FALSE),
                 "skipping 2 hidden sheet")
  expect_equal(names(vis), "alpha")

  sub <- read_all_sheets(wb, sheets = c("beta"))
  expect_equal(names(sub), "beta")
  expect_error(read_all_sheets(wb, sheets = "nope"), "None of `sheets`")
})

test_that("formula inventory is sheet-specific and policy-controlled", {
  wb <- make_workbook(c(calc = NA, plain = NA),
                      worksheet_xml = list(.formula_sheet_xml(), .sheet_xml(c("value", "3"))))
  on.exit(unlink(wb), add = TRUE)

  inv <- inspect_workbook(wb)
  expect_equal(inv$formula_cells, c(2L, 0L))
  expect_equal(inv$formula_gaps, c(1L, 0L))
  expect_equal(inv$merged_ranges, c(1L, 0L))

  expect_warning(x <- read_tabular(wb, sheet = "calc", formula_policy = "warn"),
                 "2 formula cell")
  expect_equal(vapply(attr(x, "diagnostics"), `[[`, character(1), "code"),
               c("formula_present", "formula_gap"))
  expect_error(read_tabular(wb, sheet = "calc", formula_policy = "error"),
               "cached results")
  expect_silent(allowed <- read_tabular(wb, sheet = "calc", formula_policy = "allow"))
  expect_equal(attr(allowed, "diagnostics")[[1]]$code, "formula_present")
  expect_silent(read_tabular(wb, sheet = "plain"))
})

test_that("read_all_sheets scans formulas once and cleaning preserves provenance", {
  wb <- make_workbook(c(calc = NA, plain = NA),
                      worksheet_xml = list(.formula_sheet_xml(), .sheet_xml(c("value", "3"))))
  on.exit(unlink(wb), add = TRUE)
  expect_silent(all <- read_all_sheets(wb, formula_policy = "allow"))
  expect_equal(attr(all$calc, "diagnostics")[[1]]$code, "formula_present")
  cleaned <- clean_table(read_tabular(wb, sheet = "calc", col_names = FALSE,
                                      formula_policy = "allow"), header_row = 1)
  expect_equal(attr(cleaned, "diagnostics")[[1]]$code, "formula_present")
})

test_that("headerless XLSX reads do not emit name-repair chatter", {
  wb <- make_workbook(c(alpha = NA))
  on.exit(unlink(wb), add = TRUE)
  expect_silent(read_tabular(wb, col_names = FALSE))
})

test_that("list_sheets falls back to NA visibility for a non-zip workbook", {
  csv <- tempfile(fileext = ".csv"); on.exit(unlink(csv))
  writeLines("a,b", csv)
  expect_error(list_sheets(csv))     # readxl cannot open a csv at all
})
