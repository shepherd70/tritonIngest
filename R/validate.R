# validate.R
# ---------------------------------------------------------------------------
# Generic tabular validation kernel: schema checks shared by downstream
# analysis packages (tritonmr, electrocpue, ...).
#
# Each check_*() function returns a character vector of human-readable
# failure messages (empty when the check passes) so callers can run the
# whole battery, collect every failure, and abort once via
# validation_abort(). Domain-specific rules (pass contiguity, one-first-mark,
# etc.) stay in the consuming packages; only the domain-agnostic column
# checks live here.
# ---------------------------------------------------------------------------

#' Check that required columns are present in a data frame
#'
#' @param data A data frame to check.
#' @param required Character vector of required column names. May be the
#'   names of a named type-spec vector (e.g. `c(reach_id = "character")`),
#'   in which case the names are used; an unnamed character vector is used
#'   as-is.
#' @param table_name Human-readable name of the table, used in failure
#'   messages.
#'
#' @return Character vector of failure messages; empty if all required
#'   columns are present.
#' @export
#' @family validation
check_required_columns <- function(data, required, table_name) {
  wanted <- if (!is.null(names(required))) names(required) else as.character(required)
  missing_cols <- setdiff(wanted, names(data))
  if (length(missing_cols) == 0) return(character(0))

  sprintf(
    "%s is missing required column(s): %s",
    table_name, paste(missing_cols, collapse = ", ")
  )
}

#' Check that columns have expected types
#'
#' Validates type only for columns that are present; absence is handled
#' separately by [check_required_columns()].
#'
#' @param data A data frame to check.
#' @param types Named character vector mapping column names to expected
#'   type specs (see [type_matches()]).
#' @param table_name Human-readable name of the table, used in failure
#'   messages.
#'
#' @return Character vector of failure messages; empty if all present
#'   columns are of the correct type.
#' @export
#' @family validation
check_column_types <- function(data, types, table_name) {
  present_cols <- intersect(names(types), names(data))
  if (length(present_cols) == 0) return(character(0))

  msgs <- vapply(present_cols, function(col) {
    expected <- types[[col]]
    actual   <- class(data[[col]])[1]
    if (type_matches(actual, expected)) {
      NA_character_
    } else {
      sprintf("%s$%s should be %s, found %s", table_name, col, expected, actual)
    }
  }, character(1))

  unname(msgs[!is.na(msgs)])
}

#' Check whether an actual R class satisfies an expected type spec
#'
#' `"numeric"` accepts numeric, double, and integer; `"integer"` is strict;
#' `"Date"` (or contract-style lowercase `"date"`) requires the Date class;
#' `"logical"` and `"character"` are exact. Any other spec falls back to an
#' exact class match.
#'
#' @param actual First element of `class()` of the column being checked.
#' @param expected Expected type spec string.
#'
#' @return Logical scalar.
#' @export
#' @family validation
type_matches <- function(actual, expected) {
  switch(
    expected,
    "numeric"   = actual %in% c("numeric", "integer", "double"),
    "integer"   = actual == "integer",
    "character" = actual == "character",
    "logical"   = actual == "logical",
    "Date"      = ,
    "date"      = actual == "Date",
    actual == expected
  )
}

#' Check that key columns contain no NA values
#'
#' Columns listed but absent from `data` are skipped; absence is handled
#' separately by [check_required_columns()].
#'
#' @param data A data frame to check.
#' @param columns Character vector of column names to check.
#' @param table_name Human-readable name of the table, used in failure
#'   messages.
#'
#' @return Character vector of failure messages; empty if no NAs found.
#' @export
#' @family validation
check_no_na <- function(data, columns, table_name) {
  present_cols <- intersect(columns, names(data))
  if (length(present_cols) == 0) return(character(0))

  na_counts <- vapply(present_cols, function(col) sum(is.na(data[[col]])), integer(1))
  failing <- na_counts[na_counts > 0]
  if (length(failing) == 0) return(character(0))

  unname(mapply(
    function(n, col) sprintf("%s$%s contains %d NA value(s)", table_name, col, n),
    failing, names(failing)
  ))
}

#' Check that a set of columns forms a unique key
#'
#' The validation kernel is otherwise column-level: it counts NAs and compares
#' classes, but never looks at a *record*. A repeated `(date, time)` pair -- a
#' double-entered sampling event, or two field sheets merged twice -- passes every
#' other check silently.
#'
#' @param data A data frame to check.
#' @param columns Character vector of column names forming the key. Columns
#'   absent from `data` are skipped (see [check_required_columns()]).
#' @param table_name Human-readable name of the table, used in failure messages.
#' @param max_report Maximum number of offending keys to name in the message.
#'
#' @return Character vector of failure messages; empty if the key is unique.
#' @export
#' @family validation
check_unique <- function(data, columns, table_name, max_report = 5L) {
  present <- intersect(columns, names(data))
  missing <- setdiff(columns, names(data))
  if (length(missing)) {
    return(sprintf("%s unique key is incomplete; missing column(s): %s",
                   table_name, paste(missing, collapse = ", ")))
  }
  if (length(present) == 0 || nrow(data) == 0) return(character(0))

  key <- do.call(paste, c(lapply(present, function(cc) as.character(data[[cc]])), sep = " | "))
  dup <- duplicated(key) | duplicated(key, fromLast = TRUE)
  if (!any(dup)) return(character(0))

  offenders <- unique(key[dup])
  shown <- utils::head(offenders, max_report)
  rows  <- vapply(shown, function(k) paste(which(key == k), collapse = ","), character(1))
  sprintf(
    "%s has %d row(s) sharing %d duplicated key(s) on (%s): %s%s",
    table_name, sum(dup), length(offenders), paste(present, collapse = ", "),
    paste0("'", shown, "' at rows ", rows, collapse = "; "),
    if (length(offenders) > max_report)
      sprintf(" ... and %d more", length(offenders) - max_report) else ""
  )
}

#' Check that numeric columns fall inside declared bounds
#'
#' Catches the physically impossible values that type checking cannot: a pH of
#' 42.4, a percentage survival of 150, a negative concentration.
#'
#' @param data A data frame to check.
#' @param bounds Named list mapping column name to `c(min, max)`. Use `NA` for an
#'   open end, e.g. `list(concentration = c(0, NA))`. Columns absent from `data`
#'   are skipped.
#' @param table_name Human-readable name of the table, used in failure messages.
#' @param max_report Maximum number of offending values to name per column.
#' @param report_unparseable Report populated values that cannot be parsed as
#'   numeric instead of silently skipping them.
#'
#' @return Character vector of failure messages; empty if every value is in range.
#' @export
#' @family validation
check_range <- function(data, bounds, table_name, max_report = 5L,
                        report_unparseable = TRUE) {
  if (!length(bounds)) return(character(0))
  if (is.null(names(bounds))) stop("`bounds` must be a named list.", call. = FALSE)
  present <- intersect(names(bounds), names(data))
  if (length(present) == 0) return(character(0))

  msgs <- unlist(lapply(present, function(cc) {
    lim <- bounds[[cc]]
    if (length(lim) != 2) stop("bounds[['", cc, "']] must be c(min, max).", call. = FALSE)
    raw <- data[[cc]]
    x <- suppressWarnings(as.numeric(raw))
    populated <- !is.na(raw) & nzchar(trimws(as.character(raw)))
    unparsable <- which(populated & is.na(x))
    lo <- if (is.na(lim[1])) rep(TRUE, length(x)) else x >= lim[1]
    hi <- if (is.na(lim[2])) rep(TRUE, length(x)) else x <= lim[2]
    bad <- which(!is.na(x) & !(lo & hi))
    parts <- character(0)
    if (isTRUE(report_unparseable) && length(unparsable)) {
      shown_u <- utils::head(unparsable, max_report)
      parts <- c(parts, sprintf(
        "%s$%s has %d populated value(s) that are not numeric: %s at row(s) %s%s",
        table_name, cc, length(unparsable),
        paste0("'", as.character(raw[shown_u]), "'", collapse = ", "),
        paste(shown_u, collapse = ","),
        if (length(unparsable) > max_report)
          sprintf(" ... and %d more", length(unparsable) - max_report) else ""))
    }
    if (!length(bad)) return(parts)
    shown <- utils::head(bad, max_report)
    c(parts, sprintf("%s$%s has %d value(s) outside [%s, %s]: %s at row(s) %s%s",
            table_name, cc, length(bad),
            if (is.na(lim[1])) "-Inf" else format(lim[1]),
            if (is.na(lim[2])) "Inf" else format(lim[2]),
            paste(format(x[shown]), collapse = ", "),
            paste(shown, collapse = ","),
            if (length(bad) > max_report)
              sprintf(" ... and %d more", length(bad) - max_report) else ""))
  }), use.names = FALSE)

  if (is.null(msgs)) character(0) else msgs
}

#' Check that a date/numeric column runs monotonically
#'
#' A sampling series that steps backwards usually means a mistyped year. Serial
#' 45951 sitting between 45583 and 45588 is a valid Excel date, so no type or
#' range check can see it -- only the ordering can.
#'
#' @param data A data frame to check.
#' @param column Name of the column to test. Skipped if absent from `data`.
#' @param table_name Human-readable name of the table, used in failure messages.
#' @param increasing Test for a non-decreasing (`TRUE`, the default) or
#'   non-increasing sequence.
#' @param max_gap Optional maximum permitted step between consecutive values, in
#'   the column's own units (days, for a `Date`). `NA` disables the gap check.
#' @param max_report Maximum number of offending positions to name.
#'
#' @return Character vector of failure messages; empty if monotonic.
#' @export
#' @family validation
check_monotonic <- function(data, column, table_name, increasing = TRUE,
                            max_gap = NA_real_, max_report = 5L) {
  if (!column %in% names(data)) return(character(0))
  x <- data[[column]]
  keep <- which(!is.na(x))
  if (length(keep) < 2) return(character(0))

  d <- diff(as.numeric(x[keep]))
  back <- if (isTRUE(increasing)) which(d < 0) else which(d > 0)
  msgs <- character(0)

  if (length(back)) {
    shown <- utils::head(back, max_report)
    msgs <- c(msgs, sprintf(
      "%s$%s is not %s: %d backwards step(s), e.g. %s at row(s) %s",
      table_name, column, if (isTRUE(increasing)) "non-decreasing" else "non-increasing",
      length(back),
      paste(sprintf("%s -> %s", x[keep][shown], x[keep][shown + 1]), collapse = "; "),
      paste(keep[shown + 1], collapse = ",")))
  }
  if (!is.na(max_gap)) {
    big <- which(abs(d) > max_gap)
    if (length(big)) {
      shown <- utils::head(big, max_report)
      msgs <- c(msgs, sprintf(
        "%s$%s has %d step(s) larger than %s, e.g. %s at row(s) %s",
        table_name, column, length(big), format(max_gap),
        paste(sprintf("%s -> %s", x[keep][shown], x[keep][shown + 1]), collapse = "; "),
        paste(keep[shown + 1], collapse = ",")))
    }
  }
  msgs
}

#' Abort with a classed error listing all collected validation failures
#'
#' Standardizes the collect-all-failures-then-abort pattern: run every
#' check, concatenate the returned failure messages, and call this once.
#' Does nothing when `failures` is empty, so it can be called
#' unconditionally at the end of a validator.
#'
#' @param failures Character vector of failure messages (possibly empty).
#' @param class Additional condition class for the error, prepended to
#'   `"triton_validation_error"` so callers can keep package-specific
#'   classes (e.g. `"cpue_validation_error"`).
#' @param header Optional header line; defaults to a count of issues.
#'
#' @return Invisibly `TRUE` when `failures` is empty; otherwise signals an
#'   error of class `c(class, "triton_validation_error")` whose
#'   `failures` field holds the full message vector.
#' @export
#' @family validation
validation_abort <- function(failures,
                             class = "triton_validation_error",
                             header = NULL) {
  if (length(failures) == 0) return(invisible(TRUE))

  if (is.null(header)) {
    header <- sprintf("Input validation failed with %d issue(s):", length(failures))
  }
  msg <- paste(c(header, paste0("  x ", failures)), collapse = "\n")

  stop(errorCondition(
    msg,
    failures = failures,
    class = unique(c(class, "triton_validation_error"))
  ))
}
