# read.R
# ---------------------------------------------------------------------------
# Tabular file reading and Excel-date coercion.
#
# Files are read as TEXT by default so fragile notation (non-detect "<0.01",
# leading-zero codes, mixed date encodings) survives import intact; typed
# coercion happens downstream (contract apply, censored parsing).
# ---------------------------------------------------------------------------

# File-type signatures. Dispatching on the extension alone is not safe: lab
# portals routinely serve an .xlsx workbook under a .csv name, and readr will
# happily read the ZIP's first member as if it were a compressed CSV, returning a
# one-column tibble whose name is an XML declaration. Sniff the bytes.
.ZIP_MAGIC  <- c(0x50, 0x4B, 0x03, 0x04)                              # "PK\003\004"
.OLE2_MAGIC <- c(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)      # legacy .xls

#' Identify a file's real type from its leading bytes.
#'
#' Returns the *content* type, ignoring the file name. Used by [read_tabular()]
#' to refuse a workbook wearing a `.csv` extension (and vice versa) rather than
#' silently mis-parsing it.
#'
#' @param path File path.
#' @return One of `"zip"` (an OOXML workbook: xlsx/xlsm/ods), `"ole2"` (a legacy
#'   binary xls), `"empty"` (zero bytes), or `"text"` (anything else).
#' @export
sniff_format <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  if (file.info(path)$size == 0) return("empty")
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  m <- as.integer(readBin(con, "raw", 8L))
  if (length(m) >= 4L && all(m[1:4] == .ZIP_MAGIC))  return("zip")
  if (length(m) >= 8L && all(m[1:8] == .OLE2_MAGIC)) return("ole2")
  "text"
}

# Reject an extension/content mismatch with an actionable message. `format=`
# suppresses the check, so a caller who knows better can still read the file.
.check_signature <- function(path, ext) {
  kind <- sniff_format(path)
  if (kind == "empty") return(invisible(NULL))
  txt <- c("csv", "txt", "tsv")
  if (ext %in% txt && kind %in% c("zip", "ole2")) {
    stop(sprintf(paste0(
      "read_tabular(): '%s' has a .%s extension but its contents are %s.\n",
      "  Rename the file, or pass format = \"xlsx\" (or \"xls\") to read it as a workbook."),
      basename(path), ext,
      if (kind == "zip") "a ZIP archive (an .xlsx/.ods workbook)"
      else "an OLE2 compound file (a legacy .xls workbook)"),
      call. = FALSE)
  }
  if (ext == "xlsx" && kind != "zip") {
    stop(sprintf(paste0(
      "read_tabular(): '%s' has a .xlsx extension but its contents are not a ZIP archive.\n",
      "  Pass format = \"csv\" (or the correct type) to read it as text."), basename(path)),
      call. = FALSE)
  }
  if (ext == "xls" && !kind %in% c("ole2", "zip")) {
    stop(sprintf(paste0(
      "read_tabular(): '%s' has a .xls extension but its contents are neither an OLE2 nor a ZIP file.\n",
      "  Pass format = \"csv\" (or the correct type) to read it as text."), basename(path)),
      call. = FALSE)
  }
  invisible(NULL)
}

# Read just the header with no name repair, so a duplicated source column can be
# reported *before* the reader silently makes the names unique. A duplicated
# analyte label is the signature of a copy-paste or mislabelled column.
.inspect_duplicate_header <- function(path, ext, sheet) {
  nms <- tryCatch({
    if (ext %in% c("csv", "txt")) {
      names(readr::read_csv(path, n_max = 0, name_repair = "minimal",
                            col_types = readr::cols(.default = readr::col_character()),
                            progress = FALSE))
    } else if (ext == "tsv") {
      names(readr::read_tsv(path, n_max = 0, name_repair = "minimal",
                            col_types = readr::cols(.default = readr::col_character()),
                            progress = FALSE))
    } else {
      names(readxl::read_excel(path, sheet = sheet, n_max = 0,
                               col_types = "text", .name_repair = "minimal"))
    }
  }, error = function(e) NULL, warning = function(w) NULL)
  if (is.null(nms) || !length(nms)) return(NULL)

  nms <- trimws(as.character(nms))
  real <- nms[!is.na(nms) & nzchar(nms)]
  dups <- unique(real[duplicated(real)])
  if (!length(dups)) return(NULL)

  where <- vapply(dups, function(d) paste(which(nms == d), collapse = ", "), character(1))
  data.frame(original = rep(dups, lengths(strsplit(where, ", ", fixed = TRUE))),
             position = unlist(lapply(dups, function(d) which(nms == d))),
             stringsAsFactors = FALSE)
}

#' Read a tabular data file (CSV/TSV/XLSX) as all-text columns.
#'
#' Every column is read as character so notation like non-detect markers
#' (`"<0.01"`, `"ND"`) and codes with leading zeros are preserved for downstream
#' parsing. Pass `col_types` to override on a typed read when that is not needed.
#'
#' The file's leading bytes are checked against its extension (see
#' [sniff_format()]): an `.xlsx` workbook served under a `.csv` name is an error,
#' not a silent mis-parse. Pass `format=` to override the extension entirely.
#'
#' Duplicate names in the source header are reported with a warning before the
#' underlying reader makes them unique.
#'
#' @param path File path. The extension selects the reader (csv/txt, tsv,
#'   xlsx/xls) unless `format` is given.
#' @param sheet Sheet name or index for Excel files (default: first sheet). Use
#'   [list_sheets()] to enumerate a workbook and [read_all_sheets()] to read them
#'   all -- `read_tabular()` reads exactly one sheet.
#' @param col_types Optional column-type spec passed through to the underlying
#'   reader; default reads everything as text.
#' @param col_names Treat the first row as the header (`TRUE`, the default) or
#'   read every row as data with positional names (`FALSE`). Use `FALSE` when a
#'   workbook has title/metadata rows above the real header, then recover it with
#'   [clean_table()].
#' @param format Force a reader: one of `"csv"`, `"tsv"`, `"txt"`, `"xlsx"`,
#'   `"xls"`. Defaults to `NULL` (derive from the extension and verify against the
#'   file's signature).
#' @param duplicate_names Policy for populated duplicate source headers. The
#'   default `"error"` fails closed; `"warn"` or `"repair"` allow the reader's
#'   unique-name repair and attach a `name_repairs` attribute.
#' @return A tibble.
#' @export
read_tabular <- function(path, sheet = NULL, col_types = NULL, col_names = TRUE,
                         format = NULL,
                         duplicate_names = c("error", "warn", "repair")) {
  duplicate_names <- match.arg(duplicate_names)
  if (!file.exists(path)) stop("File not found: ", path)

  if (is.null(format)) {
    ext <- tolower(tools::file_ext(path))
    if (ext %in% c("csv", "txt", "tsv", "xlsx", "xls")) .check_signature(path, ext)
  } else {
    ext <- tolower(as.character(format)[1])
    if (!ext %in% c("csv", "txt", "tsv", "xlsx", "xls")) {
      stop("Unsupported `format`: ", ext, " (use csv, txt, tsv, xlsx, or xls)", call. = FALSE)
    }
  }

  repairs <- if (isTRUE(col_names)) .inspect_duplicate_header(path, ext, sheet) else NULL
  if (!is.null(repairs)) {
    detail <- paste0("'", unique(repairs$original), "' at positions ",
                     vapply(unique(repairs$original), function(d)
                       paste(repairs$position[repairs$original == d], collapse = ", "),
                       character(1)), collapse = "; ")
    msg <- paste0("read_tabular(): duplicate source header(s): ", detail,
                  ". A duplicated label can identify different variables; repair ",
                  "does not make the meaning safe.")
    if (duplicate_names == "error") stop(msg, call. = FALSE)
    if (duplicate_names == "warn") warning(msg, call. = FALSE)
  }

  out <- if (ext %in% c("csv", "txt")) {
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
  if (!is.null(repairs)) {
    repairs$repaired <- names(out)[repairs$position]
    attr(out, "name_repairs") <- repairs
    attr(out, "diagnostics") <- list(.duplicate_header_diagnostic(repairs, "read"))
  }
  out
}

# Translate a strptime format into an anchored regex the whole string must match.
#
# This exists because base as.Date()/strptime() ignore *unconsumed trailing
# characters*: as.Date("18-08-2024", "%Y-%m-%d") consumes %Y="18", %m="08",
# %d="20", discards the trailing "24", and returns 0018-08-20 -- a valid Date, no
# warning, no NA. Requiring a full match makes a day-first string fail the
# year-first formats instead of being silently relocated to the 1st century.
.fmt_regex <- function(fmt) {
  esc <- function(ch) if (grepl("[[:alnum:]]", ch)) ch
                      else if (ch %in% c(".", "\\", "|", "(", ")", "[", "]",
                                         "{", "}", "^", "$", "*", "+", "?")) paste0("\\", ch)
                      else ch
  out <- ""
  i <- 1L
  n <- nchar(fmt)
  while (i <= n) {
    ch <- substr(fmt, i, i)
    if (ch == "%" && i < n) {
      code <- substr(fmt, i + 1L, i + 1L)
      piece <- switch(code,
        Y = "[0-9]{4}",  y = "[0-9]{2}",
        m = "[0-9]{1,2}", d = "[0-9]{1,2}", e = "[ ]?[0-9]{1,2}",
        H = "[0-9]{1,2}", M = "[0-9]{1,2}", S = "[0-9]{1,2}",
        j = "[0-9]{1,3}",
        b = "[A-Za-z]{3,}", B = "[A-Za-z]+",
        "%" = "%",
        NULL)
      if (is.null(piece)) {
        stop("coerce_excel_date(): unsupported format code '%", code,
             "' in `formats`. Supported: %Y %y %m %d %e %H %M %S %j %b %B %%.",
             call. = FALSE)
      }
      out <- paste0(out, piece)
      i <- i + 2L
    } else {
      out <- paste0(out, esc(ch))
      i <- i + 1L
    }
  }
  paste0("^", out, "$")
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
#' would silently misread ambiguous values such as `"05/06/2024"`.
#'
#' @section Strict format matching:
#' Base `as.Date()` accepts a format that consumes only a *prefix* of the string.
#' `as.Date("18-08-2024", "%Y-%m-%d")` therefore returns `0018-08-20` rather than
#' `NA`: `%Y` takes `"18"` and the trailing `"24"` is discarded. With
#' `strict = TRUE` (the default) an element must match a format over its **whole
#' length** before the parse is accepted, so day-first strings fall through to the
#' unparsed branch and are reported. Set `strict = FALSE` for the old, lenient
#' behaviour.
#'
#' A non-empty value matching neither a serial nor any format becomes `NA` *with a
#' warning*, so a silently-dropped date column does not pass unnoticed. Leading
#' and trailing whitespace (including the newlines Excel leaves in wrapped cells)
#' is trimmed before matching.
#'
#' The Excel **1900** date system is the default (`origin = "1899-12-30"`, so
#' serial 1 is 1900-01-01); pass `origin = "1904-01-01"` for a workbook saved
#' under the Mac/1904 system. There is no way to detect the date system from the
#' values alone.
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
#'   otherwise be misread as serials. Values in 1500-2500 that are treated as
#'   serials raise a warning, because they are far more often bare years than
#'   dates in 1904-1906.
#' @param strict Require a format to match an element over its whole length
#'   before accepting the parse. See *Strict format matching*.
#' @return A `Date` vector the same length as `x`.
#' @export
coerce_excel_date <- function(x,
                              formats = c("%Y-%m-%d", "%Y/%m/%d"),
                              origin = "1899-12-30",
                              serial_range = c(1, 2958465),
                              strict = TRUE) {
  if (inherits(x, "Date")) return(x)
  parsed_origin <- tryCatch(as.Date(origin), error = function(e) as.Date(NA))
  if (length(origin) != 1L || is.na(origin) || is.na(parsed_origin)) {
    stop("`origin` must be one valid Date value.", call. = FALSE)
  }
  if (!is.character(formats) || !length(formats) || anyNA(formats) ||
      any(!nzchar(formats))) {
    stop("`formats` must be a non-empty character vector.", call. = FALSE)
  }
  if (!is.numeric(serial_range) || length(serial_range) != 2L ||
      anyNA(serial_range) || serial_range[1] > serial_range[2]) {
    stop("`serial_range` must be two ordered, non-missing numbers.", call. = FALSE)
  }
  if (length(strict) != 1L || is.na(strict)) {
    stop("`strict` must be TRUE or FALSE.", call. = FALSE)
  }
  serial    <- suppressWarnings(as.numeric(x))
  is_serial <- !is.na(serial) & serial >= serial_range[1] & serial <= serial_range[2]

  out <- as.Date(rep(NA_real_, length(x)), origin = "1970-01-01")
  out[is_serial] <- as.Date(serial[is_serial], origin = origin)

  # A bare year read as a serial is the classic silent misread (2024 -> 1905-07-16).
  yearish <- is_serial & serial >= 1500 & serial <= 2500 & serial == round(serial)
  if (any(yearish)) {
    warning("coerce_excel_date(): ", sum(yearish),
            " value(s) in 1500-2500 (", paste0(utils::head(unique(serial[yearish]), 3),
            collapse = ", "),
            ") were treated as Excel serials, i.e. dates in 1904-1906. If these are ",
            "bare years, pass `serial_range = c(10000, 60000)`.", call. = FALSE)
  }

  # Parse the remaining (string) elements against each format in turn; the first
  # format that yields a valid date for an element wins. Whitespace/newlines that
  # Excel leaves in wrapped cells are trimmed before matching.
  s <- trimws(as.character(x))
  for (fmt in formats) {
    todo <- which(!is_serial & is.na(out) & !is.na(s) & nzchar(s))
    if (!length(todo)) break
    cand <- if (isTRUE(strict)) todo[grepl(.fmt_regex(fmt), s[todo])] else todo
    if (!length(cand)) next
    parsed <- as.Date(s[cand], format = fmt)
    ok <- !is.na(parsed)
    out[cand[ok]] <- parsed[ok]
  }

  unparsed <- !is_serial & is.na(out) & !is.na(x) & nzchar(s)
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
