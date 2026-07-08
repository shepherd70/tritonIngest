# sheets.R
# ---------------------------------------------------------------------------
# Worksheet enumeration.
#
# read_tabular() reads exactly one sheet, and with `sheet = NULL` that is silently
# the first one. A caller asked to "load the workbook" therefore ingested one
# sheet and never learned the others existed. These functions expose the sheet
# list -- including each sheet's visibility, which readxl does not report -- and
# read them all.
#
# Visibility is read straight out of xl/workbook.xml, because a `veryHidden`
# sheet is indistinguishable from a visible one through readxl::excel_sheets().
# ---------------------------------------------------------------------------

# Pull an XML attribute out of a tag, returning NA when absent.
.xml_attr <- function(tag, name) {
  m <- regmatches(tag, regexpr(paste0(name, '="[^"]*"'), tag))
  if (!length(m)) return(NA_character_)
  sub(paste0('^', name, '="'), "", sub('"$', "", m))
}

# XML entity decode for the handful of entities Excel writes into sheet names.
.xml_unescape <- function(x) {
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x <- gsub("&quot;", '"', x, fixed = TRUE)
  x <- gsub("&apos;", "'", x, fixed = TRUE)
  gsub("&amp;", "&", x, fixed = TRUE)   # last: an escaped & must not re-decode
}

#' List the worksheets of a workbook, with their visibility.
#'
#' `readxl::excel_sheets()` returns every sheet's name but not whether Excel
#' hides it: a `veryHidden` sheet in position 1 is what `read_tabular()` reads by
#' default, with no signal. This reads `xl/workbook.xml` directly to recover the
#' `state` attribute.
#'
#' For a legacy `.xls` (OLE2) workbook, or any file whose `workbook.xml` cannot be
#' parsed, the names still come back but `visible` is `NA`.
#'
#' @param path Path to an `.xlsx`/`.xlsm`/`.xls` workbook.
#' @return A tibble with `index` (1-based sheet position, as accepted by
#'   `read_tabular(sheet = )`), `name`, and `visible` (`"visible"`, `"hidden"`,
#'   `"veryHidden"`, or `NA`).
#' @export
list_sheets <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  names_vec <- readxl::excel_sheets(path)
  unknown <- tibble::tibble(index = seq_along(names_vec), name = names_vec,
                            visible = NA_character_)
  if (sniff_format(path) != "zip") return(unknown)

  state <- tryCatch({
    members <- utils::unzip(path, list = TRUE)$Name
    wb <- grep("^xl/workbook[.]xml$", members, value = TRUE)
    if (!length(wb)) stop("no workbook.xml")
    ex <- tempfile("triton-sheets-")
    dir.create(ex)
    on.exit(unlink(ex, recursive = TRUE), add = TRUE)
    utils::unzip(path, files = wb, exdir = ex)
    xml <- paste(readLines(file.path(ex, wb), warn = FALSE, encoding = "UTF-8"),
                 collapse = "")
    tags <- regmatches(xml, gregexpr("<sheet [^>]*?/>", xml))[[1]]
    if (!length(tags)) stop("no <sheet> tags")
    nm <- .xml_unescape(vapply(tags, .xml_attr, character(1), "name", USE.NAMES = FALSE))
    st <- vapply(tags, .xml_attr, character(1), "state", USE.NAMES = FALSE)
    st[is.na(st)] <- "visible"
    stats::setNames(st, nm)
  }, error = function(e) NULL, warning = function(w) NULL)

  if (is.null(state)) return(unknown)
  tibble::tibble(index = seq_along(names_vec), name = names_vec,
                 visible = unname(state[names_vec]))
}

#' Read every worksheet of a workbook.
#'
#' The multi-sheet counterpart to [read_tabular()], which reads exactly one sheet.
#' Sheets that fail to read (an empty sheet, a chart sheet) are reported and
#' skipped rather than aborting the whole workbook.
#'
#' @param path Path to a workbook.
#' @param col_names,col_types Passed to [read_tabular()].
#' @param include_hidden Read `hidden` / `veryHidden` sheets too (the default).
#'   Set `FALSE` to read only what a user would see in Excel.
#' @param sheets Optional character vector of sheet names, or integer positions,
#'   to restrict the read to.
#' @return A named list of tibbles, one per sheet read, in workbook order. Each
#'   carries a `sheet_visibility` attribute.
#' @export
read_all_sheets <- function(path, col_names = TRUE, col_types = NULL,
                            include_hidden = TRUE, sheets = NULL) {
  info <- list_sheets(path)
  if (!is.null(sheets)) {
    keep <- if (is.numeric(sheets)) info$index %in% as.integer(sheets)
            else info$name %in% as.character(sheets)
    if (!any(keep)) {
      stop("None of `sheets` were found. Available: ",
           paste0("'", info$name, "'", collapse = ", "), call. = FALSE)
    }
    info <- info[keep, , drop = FALSE]
  }
  if (!include_hidden) {
    hid <- !is.na(info$visible) & info$visible != "visible"
    if (any(hid)) {
      message("read_all_sheets(): skipping ", sum(hid), " hidden sheet(s): ",
              paste0("'", info$name[hid], "'", collapse = ", "))
    }
    info <- info[!hid, , drop = FALSE]
  }

  out <- vector("list", nrow(info))
  names(out) <- info$name
  failed <- character(0)
  for (i in seq_len(nrow(info))) {
    res <- tryCatch(
      read_tabular(path, sheet = info$name[i], col_types = col_types,
                   col_names = col_names),
      error = function(e) {
        failed <<- c(failed, sprintf("'%s': %s", info$name[i], conditionMessage(e)))
        NULL
      })
    if (!is.null(res)) attr(res, "sheet_visibility") <- info$visible[i]
    out[[i]] <- res
  }
  if (length(failed)) {
    warning("read_all_sheets(): ", length(failed), " sheet(s) could not be read:\n  ",
            paste(failed, collapse = "\n  "), call. = FALSE)
  }
  out[!vapply(out, is.null, logical(1))]
}
