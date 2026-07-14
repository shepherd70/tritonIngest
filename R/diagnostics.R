# diagnostics.R
# Language-neutral structured issues shared with tabular-ingestion-spec v1.

#' Build a structured tabular-ingestion diagnostic
#'
#' @param code Stable snake-case diagnostic code.
#' @param severity One of `"info"`, `"warning"`, or `"error"`.
#' @param stage Processing stage.
#' @param message Human-readable explanation.
#' @param requires_review Does this issue require human review?
#' @param table,sheet,column Optional location labels.
#' @param source_rows One-based source row numbers.
#' @param cells Spreadsheet cell references.
#' @param details Named list of machine-readable details.
#' @return A named list conforming to `tabular-diagnostic/v1`.
#' @export
tabular_diagnostic <- function(code, severity = c("info", "warning", "error"),
                               stage, message,
                               requires_review = severity[1] != "info",
                               table = NULL, sheet = NULL, column = NULL,
                               source_rows = integer(0), cells = character(0),
                               details = list()) {
  severity <- match.arg(severity)
  stages <- c("intake", "read", "structure", "layout", "mapping",
              "coercion", "validation", "cache", "artifact", "delivery")
  if (length(code) != 1L || !grepl("^[a-z][a-z0-9_]*$", code)) {
    stop("`code` must be one snake-case diagnostic identifier.", call. = FALSE)
  }
  if (length(stage) != 1L || !stage %in% stages) {
    stop("Unsupported diagnostic `stage`: ", paste(stage, collapse = ", "),
         call. = FALSE)
  }
  if (length(message) != 1L || !nzchar(message)) {
    stop("`message` must be one non-empty string.", call. = FALSE)
  }
  if (!is.list(details) || is.null(names(details)) && length(details)) {
    stop("`details` must be a named list.", call. = FALSE)
  }
  list(
    schema = "tabular-diagnostic/v1",
    code = code,
    severity = severity,
    stage = stage,
    message = message,
    requires_review = isTRUE(requires_review),
    table = table %||% NULL,
    sheet = sheet %||% NULL,
    column = column %||% NULL,
    source_rows = as.integer(source_rows),
    cells = as.character(cells),
    details = details
  )
}

.as_diagnostics <- function(x) {
  if (is.null(x)) return(list())
  if (!is.list(x)) stop("`diagnostics` must be a list of diagnostics.", call. = FALSE)
  if (length(x) && identical(x$schema, "tabular-diagnostic/v1")) x <- list(x)
  bad <- !vapply(x, function(d) is.list(d) &&
                   identical(d$schema, "tabular-diagnostic/v1") &&
                   d$severity %in% c("info", "warning", "error"), logical(1))
  if (any(bad)) stop("Every diagnostic must conform to tabular-diagnostic/v1.",
                     call. = FALSE)
  x
}

.diagnostic_summary <- function(x) {
  x <- .as_diagnostics(x)
  sev <- if (length(x)) vapply(x, `[[`, character(1), "severity") else character(0)
  list(info = sum(sev == "info"), warning = sum(sev == "warning"),
       error = sum(sev == "error"))
}

.inherit_ingest_metadata <- function(x, source, extra_diagnostics = list()) {
  diagnostics <- c(attr(source, "diagnostics") %||% list(), extra_diagnostics)
  if (length(diagnostics)) attr(x, "diagnostics") <- diagnostics
  features <- attr(source, "workbook_features")
  if (!is.null(features)) attr(x, "workbook_features") <- features
  x
}

.duplicate_header_diagnostic <- function(repairs, stage) {
  records <- lapply(seq_len(nrow(repairs)), function(i) {
    list(original = repairs$original[[i]], repaired = repairs$repaired[[i]],
         position = as.integer(repairs$position[[i]]))
  })
  tabular_diagnostic(
    code = "duplicate_header", severity = "warning", stage = stage,
    message = "Duplicate headers were mechanically renamed; semantic identity remains unresolved.",
    requires_review = TRUE, source_rows = 1L, details = list(repairs = records)
  )
}
