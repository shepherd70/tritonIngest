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

# Read one XML member without extracting a workbook beside the source file.
.zip_xml_text <- function(path, member, listing = NULL) {
  listing <- listing %||% utils::unzip(path, list = TRUE)
  hit <- match(member, listing$Name)
  if (is.na(hit)) stop("Workbook member not found: ", member, call. = FALSE)
  con <- unz(path, member, open = "rb")
  on.exit(close(con), add = TRUE)
  raw <- readBin(con, "raw", n = listing$Length[[hit]])
  enc2utf8(rawToChar(raw))
}

.xml_tags <- function(xml, tag) {
  hits <- regmatches(xml, gregexpr(paste0("<", tag, "\\b[^>]*?/?>"), xml,
                                   perl = TRUE))[[1]]
  if (length(hits) == 1L && identical(hits, character(0))) character(0) else hits
}

.worksheet_feature_counts <- function(xml) {
  cells <- regmatches(xml, gregexpr("(?s)<c\\b[^>]*>.*?</c>", xml,
                                    perl = TRUE))[[1]]
  if (length(cells) == 1L && identical(cells, character(0))) cells <- character(0)
  formula_cells <- cells[grepl("<f(?:\\s|/|>)", cells, perl = TRUE)]
  cached <- grepl("<v\\b[^>]*>[^<]+</v>", formula_cells, perl = TRUE)
  list(
    formula_cells = length(formula_cells),
    formula_gaps = sum(!cached),
    merged_ranges = length(.xml_tags(xml, "mergeCell"))
  )
}

#' Inspect formula and merge features in an OOXML workbook
#'
#' Reads workbook XML directly, without evaluating formulas or changing the
#' source. Formula cells are counted per worksheet, along with formula cells
#' that have no cached `<v>` result and merged-cell ranges. This is intentionally
#' a small safety inventory; the Python cleanup service remains responsible for
#' detailed style, formula-text, and review-workflow inventory.
#'
#' @param path Path to an `.xlsx` workbook.
#' @param sheets Optional sheet names or one-based positions to inspect. The
#'   default scans every worksheet.
#' @return A tibble with sheet identity/visibility and integer columns
#'   `formula_cells`, `formula_gaps`, and `merged_ranges`.
#' @export
inspect_workbook <- function(path, sheets = NULL) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  if (sniff_format(path) != "zip") {
    stop("inspect_workbook() requires an OOXML ZIP workbook (.xlsx).",
         call. = FALSE)
  }
  listing <- utils::unzip(path, list = TRUE)
  wb_member <- "xl/workbook.xml"
  rel_member <- "xl/_rels/workbook.xml.rels"
  wb_xml <- .zip_xml_text(path, wb_member, listing)
  rel_xml <- .zip_xml_text(path, rel_member, listing)
  sheet_tags <- .xml_tags(wb_xml, "sheet")
  rel_tags <- .xml_tags(rel_xml, "Relationship")
  if (!length(sheet_tags) || !length(rel_tags)) {
    stop("Workbook XML does not contain readable sheet relationships.", call. = FALSE)
  }

  sheet_names <- .xml_unescape(vapply(sheet_tags, .xml_attr, character(1),
                                      "name", USE.NAMES = FALSE))
  rel_ids <- vapply(sheet_tags, .xml_attr, character(1), "r:id", USE.NAMES = FALSE)
  rel_id <- vapply(rel_tags, .xml_attr, character(1), "Id", USE.NAMES = FALSE)
  rel_target <- vapply(rel_tags, .xml_attr, character(1), "Target", USE.NAMES = FALSE)
  targets <- rel_target[match(rel_ids, rel_id)]
  targets <- gsub("\\\\", "/", targets)
  targets <- sub("^/", "", targets)
  targets <- ifelse(startsWith(targets, "xl/"), targets, paste0("xl/", targets))
  if (anyNA(targets) || any(!targets %in% listing$Name)) {
    stop("Workbook sheet relationships do not resolve to worksheet XML.", call. = FALSE)
  }

  visibility <- list_sheets(path)$visible
  out <- tibble::tibble(index = seq_along(sheet_names), name = sheet_names,
                        visible = visibility, xml_member = targets)
  if (!is.null(sheets)) {
    keep <- if (is.numeric(sheets)) out$index %in% as.integer(sheets)
            else out$name %in% as.character(sheets)
    if (!any(keep)) {
      stop("None of `sheets` were found. Available: ",
           paste0("'", out$name, "'", collapse = ", "), call. = FALSE)
    }
    out <- out[keep, , drop = FALSE]
  }

  counts <- lapply(out$xml_member, function(member) {
    .worksheet_feature_counts(.zip_xml_text(path, member, listing))
  })
  out$formula_cells <- vapply(counts, `[[`, integer(1), "formula_cells")
  out$formula_gaps <- vapply(counts, `[[`, integer(1), "formula_gaps")
  out$merged_ranges <- vapply(counts, `[[`, integer(1), "merged_ranges")
  out$xml_member <- NULL
  out
}

.apply_formula_policy <- function(x, info, policy) {
  if (is.null(info) || !nrow(info) || info$formula_cells[[1]] == 0L) return(x)
  policy <- match.arg(policy, c("warn", "error", "allow"))
  sheet <- info$name[[1]]
  count <- info$formula_cells[[1]]
  gaps <- info$formula_gaps[[1]]
  msg <- paste0("read_tabular(): sheet '", sheet, "' contains ", count,
                " formula cell(s); Excel cached results are being read as text",
                if (gaps) paste0(", and ", gaps, " formula cell(s) have no cached result") else "",
                ". Recalculate and save the workbook, or require review of formula provenance.")
  if (policy == "error") stop(msg, call. = FALSE)
  if (policy == "warn") warning(msg, call. = FALSE)

  diagnostics <- attr(x, "diagnostics") %||% list()
  diagnostics <- c(diagnostics, list(tabular_diagnostic(
    code = "formula_present", severity = "info", stage = "intake",
    message = "Worksheet contains formulas; cached Excel results were ingested.",
    requires_review = TRUE, sheet = sheet,
    details = list(formula_cells = count,
                   merged_ranges = info$merged_ranges[[1]],
                   cached_results_ingested = TRUE)
  )))
  if (gaps) {
    diagnostics <- c(diagnostics, list(tabular_diagnostic(
      code = "formula_gap", severity = "warning", stage = "intake",
      message = "Formula cells without cached results may appear blank during ingestion.",
      requires_review = TRUE, sheet = sheet,
      details = list(formula_gaps = gaps)
    )))
  }
  attr(x, "diagnostics") <- diagnostics
  attr(x, "workbook_features") <- as.list(info[1, , drop = FALSE])
  x
}

#' Read every worksheet of a workbook.
#'
#' The multi-sheet counterpart to [read_tabular()], which reads exactly one sheet.
#' Sheets that fail to read (an empty sheet, a chart sheet) are reported and
#' skipped rather than aborting the whole workbook.
#'
#' @param path Path to a workbook.
#' @param col_names,col_types Passed to [read_tabular()].
#' @param formula_policy Formula handling policy passed to [read_tabular()].
#' @param include_hidden Read `hidden` / `veryHidden` sheets too (the default).
#'   Set `FALSE` to read only what a user would see in Excel.
#' @param sheets Optional character vector of sheet names, or integer positions,
#'   to restrict the read to.
#' @return A named list of tibbles, one per sheet read, in workbook order. Each
#'   carries a `sheet_visibility` attribute.
#' @export
read_all_sheets <- function(path, col_names = TRUE, col_types = NULL,
                            include_hidden = TRUE, sheets = NULL,
                            formula_policy = c("warn", "error", "allow")) {
  formula_policy <- match.arg(formula_policy)
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

  inventory <- if (sniff_format(path) == "zip") {
    tryCatch(inspect_workbook(path, sheets = info$name), error = function(e) {
      msg <- paste0("read_all_sheets(): formula inventory failed: ", conditionMessage(e))
      if (formula_policy == "error") stop(msg, call. = FALSE)
      if (formula_policy == "warn") warning(msg, call. = FALSE)
      NULL
    })
  } else NULL

  out <- vector("list", nrow(info))
  names(out) <- info$name
  failed <- character(0)
  for (i in seq_len(nrow(info))) {
    res <- tryCatch(
      .read_tabular_impl(path, sheet = info$name[i], col_types = col_types,
                         col_names = col_names, formula_policy = formula_policy,
                         formula_info = if (is.null(inventory)) NULL else
                           inventory[inventory$name == info$name[i], , drop = FALSE],
                         inspect_formulas = FALSE),
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
