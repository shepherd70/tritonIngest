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

#' Drop label rows: rows carrying fewer than `min_cells` populated cells.
#'
#' [clean_table()] deliberately keeps every row that is not *fully* blank, because
#' deciding that a sparse row is not a record needs the schema. But two sparse-row
#' species are structural, not data, in almost every lab export: the single-cell
#' **section divider** (`"Physical Tests"`, `"Total Metals"`) that separates analyte
#' blocks, and the trailing **footnote banner**. Both carry one populated cell.
#'
#' This is the generic form of the rule; a caller that knows its schema can pass a
#' different `min_cells`.
#'
#' @param df A data frame.
#' @param min_cells Minimum number of non-blank cells a row must have to be kept.
#' @return `df` without its label rows.
#' @export
drop_label_rows <- function(df, min_cells = 2L) {
  if (!nrow(df) || !ncol(df)) return(df)
  bm <- .blank_matrix(df)
  populated <- ncol(df) - rowSums(bm)
  df[populated >= as.integer(min_cells), , drop = FALSE]
}

# Build column names from one or more header rows. A multi-row header spreads a
# name across rows (a merged group label above, a sub-name below); readxl gives
# the merged value only in its top-left cell, so pasting the non-blank pieces down
# each column reconstructs "EPH C10-C19 (mg/L)" from "…(EPH)" + "C10-C19 (mg/L)".
.promote_header <- function(df, rows, sep = " ") {
  cells <- lapply(rows, function(r) trimws(as.character(unlist(df[r, ], use.names = FALSE))))
  vapply(seq_len(ncol(df)), function(j) {
    parts <- vapply(cells, function(x) x[j], character(1))
    parts <- parts[!is.na(parts) & nzchar(parts)]
    if (!length(parts)) "" else paste(parts, collapse = sep)
  }, character(1))
}

#' Clean a freshly-read table: promote the header and strip junk.
#'
#' Locates the header row (or uses `header_row`/`header_rows`), makes it the
#' column names, drops everything above it, then removes fully-blank rows and
#' columns and optionally trims whitespace. Cell *values* are never coerced -- the
#' all-text contract from [read_tabular()] is preserved.
#'
#' Expects a header-less frame, i.e. read with `col_names = FALSE` so the real
#' header is still a data row to be found. Blank header names are filled
#' (`col_<position>`) and duplicates made unique, both with a warning: a duplicated
#' header is usually a mislabelled column, and a blank one usually means the
#' promoted row was not the whole header.
#'
#' @section What this does not do:
#' Only fully-blank rows are dropped. An embedded metadata row -- a `"Permit limit"`
#' row whose analyte cells are ordinary numbers -- survives and becomes a record.
#' Pass `drop_labels = TRUE` for the single-cell section dividers and footnote
#' banners; anything richer needs the schema, so filter it in the consumer. A
#' paginated print report with a *repeated* header every N rows is not a single
#' table at all: split it on the repeated header rows before calling this.
#'
#' @param df A data frame of all-text, header-less rows (see [read_tabular()]).
#' @param header_row Optional integer: force this row to be the header instead of
#'   detecting it.
#' @param header_rows Optional integer vector of two or more rows forming a
#'   multi-row header; their non-blank cells are pasted down each column. Takes
#'   precedence over `header_row`. The body starts after `max(header_rows)`.
#' @param trim_ws Trim leading/trailing whitespace from header and cell text.
#' @param drop_labels Also drop rows with fewer than two populated cells (see
#'   [drop_label_rows()]).
#' @param sep Separator used to join the pieces of a multi-row header.
#' @param duplicate_names Policy for duplicated promoted names. The default
#'   `"error"` fails closed; override modes attach `name_repairs` provenance.
#' @return A tibble with promoted names and structural junk removed.
#' @export
clean_table <- function(df, header_row = NULL, header_rows = NULL, trim_ws = TRUE,
                        drop_labels = FALSE, sep = " ",
                        duplicate_names = c("error", "warn", "repair")) {
  duplicate_names <- match.arg(duplicate_names)
  if (!nrow(df) || !ncol(df)) {
    return(.inherit_ingest_metadata(tibble::as_tibble(df), df))
  }

  if (!is.null(header_rows)) {
    rows <- sort(unique(as.integer(header_rows)))
    if (any(rows < 1L) || any(rows > nrow(df))) {
      stop("header_rows out of range: ", paste(rows, collapse = ", "))
    }
    nm <- .promote_header(df, rows, sep = sep)
    last <- max(rows)
  } else {
    hr <- header_row
    if (is.null(hr)) {
      hr <- find_header_row(df)
      if (is.na(hr)) {
        warning("clean_table(): could not detect a header row; using the first ",
                "non-blank row. Pass header_row= to override.")
        nonblank <- ncol(df) - rowSums(.blank_matrix(df))
        hr <- which(nonblank > 0)[1]
        if (is.na(hr)) {
          return(.inherit_ingest_metadata(tibble::as_tibble(df[0, , drop = FALSE]), df))
        }
      }
    }
    hr <- as.integer(hr)
    if (hr < 1L || hr > nrow(df)) stop("header_row out of range: ", hr)
    nm <- .promote_header(df, hr, sep = sep)
    last <- hr
  }

  # Fill blanks positionally and de-dupe -- but say so. A blank header cell over a
  # populated column, or a duplicated name, is evidence the source is malformed.
  blank <- is.na(nm) | nm == ""
  if (any(blank)) {
    populated <- vapply(which(blank), function(j) {
      body_rows <- if (last >= nrow(df)) integer(0) else (last + 1L):nrow(df)
      length(body_rows) && !all(.is_blank(df[[j]][body_rows]))
    }, logical(1))
    if (any(populated)) {
      warning("clean_table(): header cell(s) blank over populated column(s) at position(s) ",
              paste(which(blank)[populated], collapse = ", "),
              "; named 'col_<position>'. The promoted row is probably not the whole ",
              "header -- pass header_rows= for a multi-row header.", call. = FALSE)
    }
    nm[blank] <- paste0("col_", which(blank))
  }
  dups <- unique(nm[duplicated(nm)])
  repairs <- NULL
  if (length(dups)) {
    repairs <- data.frame(
      original = rep(dups, vapply(dups, function(d) sum(nm == d), integer(1))),
      position = unlist(lapply(dups, function(d) which(nm == d))),
      stringsAsFactors = FALSE
    )
    msg <- paste0("clean_table(): duplicate promoted header(s): ",
                  paste0("'", dups, "'", collapse = ", "),
                  ". Repair does not establish semantic identity.")
    if (duplicate_names == "error") stop(msg, call. = FALSE)
    if (duplicate_names == "warn") warning(msg, call. = FALSE)
  }
  nm <- make.unique(nm, sep = "_")
  if (!is.null(repairs)) repairs$repaired <- nm[repairs$position]

  body <- if (last >= nrow(df)) df[0, , drop = FALSE]
          else df[(last + 1):nrow(df), , drop = FALSE]
  names(body) <- nm

  if (isTRUE(drop_labels)) body <- drop_label_rows(body)
  body <- drop_blank_rows(body)
  body <- drop_blank_cols(body)

  if (isTRUE(trim_ws)) {
    chr <- which(vapply(body, is.character, logical(1)))
    for (j in chr) body[[j]] <- trimws(body[[j]])
  }
  body <- tibble::as_tibble(body)
  extra_diagnostics <- list()
  if (!is.null(repairs)) {
    attr(body, "name_repairs") <- repairs
    extra_diagnostics <- list(.duplicate_header_diagnostic(repairs, "structure"))
  }
  .inherit_ingest_metadata(body, df, extra_diagnostics)
}
