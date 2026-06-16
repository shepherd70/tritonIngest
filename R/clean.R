# clean.R
# ---------------------------------------------------------------------------
# Cleaning structural junk out of a freshly-read table: locate the real header
# row, promote it to column names, and strip blank rows/columns and stray
# whitespace.
#
# Field and lab workbooks rarely put the header on row 1. They carry title and
# metadata rows above it, blank spacer rows and columns, and trailing notes.
# These functions run *between* read_tabular() (read header-less, every row as
# data) and detect_layout(): they fix the table's shape without touching cell
# semantics -- no type coercion, so the all-text contract from read_tabular()
# survives.
#
# Intended use:
#   raw   <- read_tabular(path, sheet = "Data", col_names = FALSE)
#   tidy  <- clean_table(raw)
#   detect_layout(tidy) ...
#
# Scope note: only *fully blank* rows and columns are removed. Trailing notes /
# subtotal rows that still carry text are left in place on purpose -- deciding
# they are not real records needs the schema, which is the consumer's job via
# validate_against_contract(). Dropping them here would risk discarding genuine
# sparse records.
# ---------------------------------------------------------------------------

# Blank == NA or empty after trimming. Element-wise on a vector.
.is_blank <- function(x) is.na(x) | trimws(as.character(x)) == ""

# Logical matrix (nrow x ncol) flagging blank cells; robust to 1-row frames.
.blank_matrix <- function(df) {
  matrix(
    vapply(df, .is_blank, logical(nrow(df))),
    nrow = nrow(df), ncol = ncol(df)
  )
}

#' Drop fully-blank rows from a data frame.
#'
#' A row is blank when every cell is `NA` or empty after trimming whitespace.
#'
#' @param df A data frame.
#' @return `df` without its fully-blank rows.
#' @export
drop_blank_rows <- function(df) {
  if (!nrow(df) || !ncol(df)) return(df)
  bm <- .blank_matrix(df)
  df[rowSums(bm) < ncol(df), , drop = FALSE]
}

#' Drop fully-blank columns from a data frame.
#'
#' A column is blank when every cell is `NA` or empty after trimming whitespace.
#' Removes the empty spacer columns common in spreadsheet exports.
#'
#' @param df A data frame.
#' @return `df` without its fully-blank columns.
#' @export
drop_blank_cols <- function(df) {
  if (!nrow(df) || !ncol(df)) return(df)
  bm <- .blank_matrix(df)
  df[, colSums(bm) < nrow(df), drop = FALSE]
}

#' Find the most likely header row in a header-less table.
#'
#' Given a frame read with every row as data (`read_tabular(path,
#' col_names = FALSE)`), guess which row holds the column names. Leading blank
#' rows and sparse title/metadata rows are skipped; the header is taken to be the
#' first well-populated row whose own cells look like names rather than values,
#' and that has data beneath it. Reuses [is_value_like()] to tell names from
#' values.
#'
#' This is a heuristic and is meant to be overridable: when nothing is
#' convincing it returns `NA` so the caller can fall back or pass an explicit
#' `header_row` to [clean_table()].
#'
#' @param df A data frame of all-text, header-less rows.
#' @param max_scan Maximum number of leading rows to examine for the header.
#' @return Integer row index of the header, or `NA_integer_` if none is found.
#' @export
find_header_row <- function(df, max_scan = 20L) {
  n <- nrow(df); w <- ncol(df)
  if (!n || !w) return(NA_integer_)
  scan_n <- min(as.integer(max_scan), n)
  bm <- .blank_matrix(df)
  nonblank <- w - rowSums(bm)                 # populated cells per row
  if (all(nonblank == 0)) return(NA_integer_)
  max_fill <- max(nonblank[seq_len(scan_n)])
  min_fill <- max(2, 0.6 * max_fill)          # skip blank rows & sparse titles

  for (i in seq_len(scan_n)) {
    if (nonblank[i] < min_fill) next          # blank or sparse (title/metadata)
    cells <- trimws(as.character(unlist(df[i, ], use.names = FALSE)))
    cells <- cells[!is.na(cells) & cells != ""]
    frac_value <- mean(vapply(cells, is_value_like, logical(1)))
    if (isTRUE(frac_value > 0.5)) next        # this row reads as data, not header
    if (i >= n) next                          # nothing below to be data
    if (all(.blank_matrix(df[(i + 1):n, , drop = FALSE]))) next  # no data under it
    return(i)
  }
  NA_integer_
}

#' Clean a freshly-read table: promote the header and strip junk.
#'
#' Locates the header row (or uses `header_row`), makes it the column names,
#' drops everything above it, then removes fully-blank rows and columns and
#' optionally trims whitespace. Cell *values* are never coerced -- the all-text
#' contract from [read_tabular()] is preserved.
#'
#' Expects a header-less frame, i.e. read with `col_names = FALSE` so the real
#' header is still a data row to be found. Blank or duplicated header names are
#' filled (`col_<position>`) and made unique rather than silently collapsed.
#' Only fully blank rows/columns are dropped (see the note in `clean.R`).
#'
#' @param df A data frame of all-text, header-less rows (see [read_tabular()]).
#' @param header_row Optional integer: force this row to be the header instead of
#'   detecting it.
#' @param trim_ws Trim leading/trailing whitespace from header and cell text.
#' @return A tibble with promoted names and structural junk removed.
#' @export
clean_table <- function(df, header_row = NULL, trim_ws = TRUE) {
  if (!nrow(df) || !ncol(df)) return(tibble::as_tibble(df))

  hr <- header_row
  if (is.null(hr)) {
    hr <- find_header_row(df)
    if (is.na(hr)) {
      warning("clean_table(): could not detect a header row; using the first ",
              "non-blank row. Pass header_row= to override.")
      nonblank <- ncol(df) - rowSums(.blank_matrix(df))
      hr <- which(nonblank > 0)[1]
      if (is.na(hr)) return(tibble::as_tibble(df[0, , drop = FALSE]))
    }
  }
  hr <- as.integer(hr)
  if (hr < 1L || hr > nrow(df)) stop("header_row out of range: ", hr)

  # Promote the header row to names: trim, fill blanks positionally, de-dupe.
  nm <- trimws(as.character(unlist(df[hr, ], use.names = FALSE)))
  blank <- is.na(nm) | nm == ""
  nm[blank] <- paste0("col_", which(blank))
  nm <- make.unique(nm, sep = "_")

  body <- if (hr >= nrow(df)) df[0, , drop = FALSE]
          else df[(hr + 1):nrow(df), , drop = FALSE]
  names(body) <- nm

  body <- drop_blank_rows(body)
  body <- drop_blank_cols(body)

  if (isTRUE(trim_ws)) {
    chr <- which(vapply(body, is.character, logical(1)))
    for (j in chr) body[[j]] <- trimws(body[[j]])
  }
  tibble::as_tibble(body)
}
