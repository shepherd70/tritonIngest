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
