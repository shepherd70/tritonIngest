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
#' @return A tibble.
#' @export
read_tabular <- function(path, sheet = NULL, col_types = NULL) {
  if (!file.exists(path)) stop("File not found: ", path)
  ext <- tolower(tools::file_ext(path))

  if (ext %in% c("csv", "txt")) {
    ct <- col_types %||% readr::cols(.default = readr::col_character())
    readr::read_csv(path, col_types = ct, progress = FALSE)
  } else if (ext == "tsv") {
    ct <- col_types %||% readr::cols(.default = readr::col_character())
    readr::read_tsv(path, col_types = ct, progress = FALSE)
  } else if (ext %in% c("xlsx", "xls")) {
    readxl::read_excel(path, sheet = sheet, col_types = col_types %||% "text")
  } else {
    stop("Unsupported file type: .", ext, " (use CSV, TSV, or XLSX)")
  }
}

#' Coerce mixed Excel-serial / ISO-string dates to Date.
#'
#' Worksheet date columns ingested from Excel sometimes arrive as a mix of Excel
#' serial numbers (e.g. `"45909"` or `45909`) and ISO date strings (e.g.
#' `"2023-08-22"`), depending on how each cell was formatted. A naive `as.Date()`
#' mangles the serials and a naive serial conversion drops the ISO strings to
#' `NA`. This detects each element's encoding and coerces both to a single `Date`
#' vector (1900 date system, origin 1899-12-30), leaving genuinely
#' missing/unparseable values as `NA`.
#'
#' @param x A vector (numeric or character) of Excel-serial numbers and/or ISO
#'   `"YYYY-MM-DD"` strings.
#' @return A `Date` vector the same length as `x`.
#' @export
coerce_excel_date <- function(x) {
  serial    <- suppressWarnings(as.numeric(x))
  is_serial <- !is.na(serial)

  out <- as.Date(rep(NA_real_, length(x)), origin = "1970-01-01")
  # Excel 1900 date system: serial 1 == 1900-01-01, so origin is 1899-12-30.
  out[is_serial]  <- as.Date(serial[is_serial], origin = "1899-12-30")
  out[!is_serial] <- as.Date(as.character(x)[!is_serial], format = "%Y-%m-%d")
  out
}
