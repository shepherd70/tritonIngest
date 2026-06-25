# read.R
# ---------------------------------------------------------------------------
# Tabular file reading and Excel-date coercion.
#
# Files are read as TEXT by default so fragile notation (non-detect "<0.01",
# leading-zero codes, mixed date encodings) survives import intact; typed
# coercion happens downstream (contract apply, censored parsing).
# ---------------------------------------------------------------------------

#' Read a tabular data file (CSV/TSV/XLSX) as all-text columns.
#'
#' Every column is read as character so notation like non-detect markers
#' (`"<0.01"`, `"ND"`) and codes with leading zeros are preserved for downstream
#' parsing. Pass `col_types` to override on a typed read when that is not needed.
#'
#' @param path File path. The extension selects the reader (csv/txt, tsv,
#'   xlsx/xls).
#' @param sheet Sheet name or index for Excel files (default: first sheet).
#' @param col_types Optional column-type spec passed through to the underlying
#'   reader; default reads everything as text.
#' @param col_names Treat the first row as the header (`TRUE`, the default) or
#'   read every row as data with positional names (`FALSE`). Use `FALSE` when a
#'   workbook has title/metadata rows above the real header, then recover it with
#'   [clean_table()].
#' @return A tibble.
#' @export
read_tabular <- function(path, sheet = NULL, col_types = NULL, col_names = TRUE) {
  if (!file.exists(path)) stop("File not found: ", path)
  ext <- tolower(tools::file_ext(path))

  if (ext %in% c("csv", "txt")) {
    ct <- col_types %||% readr::cols(.default = readr::col_character())
    readr::read_csv(path, col_names = col_names, col_types = ct, progress = FALSE)
  } else if (ext == "tsv") {
    ct <- col_types %||% readr::cols(.default = readr::col_character())
    readr::read_tsv(path, col_names = col_names, col_types = ct, progress = FALSE)
  } else if (ext %in% c("xlsx", "xls")) {
    readxl::read_excel(path, sheet = sheet, col_names = col_names,
                       col_types = col_types %||% "text")
  } else {
    stop("Unsupported file type: .", ext, " (use CSV, TSV, or XLSX)")
  }
}

#' Coerce mixed Excel-serial / date-string values to Date.
#'
#' Worksheet date columns ingested from Excel often arrive as a mix of Excel
#' serial numbers (e.g. `"45909"` or `45909`) and date strings (e.g.
#' `"2023-08-22"`), depending on how each cell was formatted. A naive `as.Date()`
#' mangles the serials and a naive serial conversion drops the strings to `NA`.
#' This detects each element's encoding and coerces both to a single `Date`
#' vector, leaving genuinely missing/unparseable values as `NA`.
#'
#' Detection is by value: anything that parses as a number *within*
#' `serial_range` is treated as an Excel serial; every other non-empty element is
#' parsed against `formats` in order (first match wins, per element). The default
#' `formats` are the unambiguous **year-first** layouts; pass `formats` for day-
#' or month-first data (e.g. `"%d/%m/%Y"`) rather than relying on a guess, which
#' would silently misread ambiguous values such as `"05/06/2024"`. A non-empty
#' value matching neither a serial nor any format becomes `NA` *with a warning*,
#' so a silently-dropped date column does not pass unnoticed.
#'
#' The Excel **1900** date system is the default (`origin = "1899-12-30"`, so
#' serial 1 is 1900-01-01); pass `origin = "1904-01-01"` for a workbook saved
#' under the Mac/1904 system.
#'
#' @param x A vector (numeric or character) of Excel-serial numbers and/or date
#'   strings.
#' @param formats Character vector of [strptime()] formats tried, in order, for
#'   string (non-serial) elements. Defaults to year-first ISO layouts.
#' @param origin Date origin for Excel serials: `"1899-12-30"` (1900 system,
#'   default) or `"1904-01-01"` (1904 system).
#' @param serial_range Length-2 `c(min, max)` bounding which numbers are treated
#'   as Excel serials. Defaults to the full valid Excel range; tighten it (e.g.
#'   `c(10000, 60000)`) when bare year-like integers like `"2024"` would
#'   otherwise be misread as serials.
#' @return A `Date` vector the same length as `x`.
#' @export
coerce_excel_date <- function(x,
                              formats = c("%Y-%m-%d", "%Y/%m/%d"),
                              origin = "1899-12-30",
                              serial_range = c(1, 2958465)) {
  serial    <- suppressWarnings(as.numeric(x))
  is_serial <- !is.na(serial) & serial >= serial_range[1] & serial <= serial_range[2]

  out <- as.Date(rep(NA_real_, length(x)), origin = "1970-01-01")
  out[is_serial] <- as.Date(serial[is_serial], origin = origin)

  # Parse the remaining (string) elements against each format in turn; the first
  # format that yields a valid date for an element wins.
  s <- as.character(x)
  for (fmt in formats) {
    todo <- which(!is_serial & is.na(out) & !is.na(s) & nzchar(trimws(s)))
    if (!length(todo)) break
    parsed <- as.Date(s[todo], format = fmt)
    ok <- !is.na(parsed)
    out[todo[ok]] <- parsed[ok]
  }

  unparsed <- !is_serial & is.na(out) & !is.na(x) & nzchar(trimws(s))
  if (any(unparsed)) {
    ex <- unique(s[unparsed])
    warning("coerce_excel_date(): ", sum(unparsed),
            " value(s) matched neither an Excel serial nor a known date format (",
            paste0("'", utils::head(ex, 3), "'", collapse = ", "),
            if (length(ex) > 3) ", ..." else "",
            "); returned NA. Pass `formats=` for other date layouts.",
            call. = FALSE)
  }
  out
}
