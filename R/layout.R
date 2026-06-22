# layout.R
# ---------------------------------------------------------------------------
# Long/wide layout detection and wide -> long reshaping.
#
# A "long/tidy" table has one measurement per row (a parameter column and a
# value column). A "wide" table spreads measured variables across columns. These
# heuristics pick a default; the caller can always override.
# ---------------------------------------------------------------------------

#' Does a character vector look numeric-ish (allowing non-detect notation)?
#'
#' Used by layout detection: a measured-variable column in a wide file contains
#' numbers and possibly non-detect entries (`"<DL"`, `"ND"`).
#'
#' @param x Character vector.
#' @param threshold Minimum fraction of non-missing entries that must parse as a
#'   number or a recognised non-detect token.
#' @return `TRUE`/`FALSE`.
#' @export
is_value_like <- function(x, threshold = 0.8) {
  x <- x[!is.na(x) & trimws(x) != ""]
  if (!length(x)) return(FALSE)
  x <- trimws(x)
  numeric_ok <- suppressWarnings(!is.na(as.numeric(x)))
  nd_ok <- grepl("^<\\s*[0-9.eE+-]+$", x) |
    toupper(x) %in% c("ND", "N.D.", "BDL", "DNQ", "U")
  mean(numeric_ok | nd_ok) >= threshold
}

#' Heuristically detect whether a table is long/tidy or wide.
#'
#' Long signals: a parameter-ish column name AND a value-ish column name, or a
#' single value-like column. Wide signals: two or more value-like columns
#' (variables spread across columns). The caller can override the result.
#'
#' Column names are matched case-insensitively and after trimming surrounding
#' whitespace, so a header exported as `"Analyte "` (a trailing space is common
#' in lab reports) still hits the vocabulary. The default vocabularies carry both
#' singular and plural forms (`"result"`/`"results"`, `"analyte"`/`"analytes"`,
#' ...) because labs are inconsistent: an ALS export, for instance, labels its
#' value column `"Results"`. Missing the plural would drop the long signal and,
#' when two or more numeric columns are present (value + detection limit + a
#' numeric QC-lot id), misclassify the table as wide.
#'
#' @param df A data frame (typically read all-text via [read_tabular()]).
#' @param param_names,value_names Character vectors of lowercase column names
#'   that signal a long-format parameter / value column. Matched after
#'   lowercasing and whitespace-trimming the data's names. Override to match a
#'   domain's vocabulary.
#' @return A list: `layout` (`"long"`/`"wide"`), `value_like_cols`, `reason`.
#' @export
detect_layout <- function(df,
                          param_names = c("parameter", "parameters",
                                          "param", "params",
                                          "analyte", "analytes",
                                          "characteristic", "characteristics",
                                          "characteristicname",
                                          "variable", "variables",
                                          "constituent", "constituents"),
                          value_names = c("value", "values",
                                          "result", "results", "resultvalue",
                                          "value_raw",
                                          "concentration", "concentrations",
                                          "conc",
                                          "measurement", "measurements")) {
  nms <- trimws(tolower(names(df)))
  param_name_hit <- nms %in% param_names
  value_name_hit <- nms %in% value_names

  value_like <- vapply(df, is_value_like, logical(1))
  # An id/date column can look numeric; don't count obvious id/date columns.
  idish <- nms %in% c("row", "id", "sample_id", "sampleid", "index") |
    grepl("date|time", nms)
  value_like_cols <- names(df)[value_like & !idish]

  if (any(param_name_hit) && any(value_name_hit)) {
    layout <- "long"
    reason <- "found parameter and value column names"
  } else if (length(value_like_cols) >= 2) {
    layout <- "wide"
    reason <- paste0(length(value_like_cols), " value-like columns: ",
                     paste(value_like_cols, collapse = ", "))
  } else if (any(param_name_hit) || length(value_like_cols) == 1) {
    layout <- "long"
    reason <- "single value-like column"
  } else {
    layout <- "long"
    reason <- "no clear signal; defaulting to long - please confirm"
  }

  list(layout = layout, value_like_cols = value_like_cols, reason = reason)
}

#' Melt a wide table (variables as columns) to long form.
#'
#' @param df Wide data frame.
#' @param param_cols Character vector of measured-variable column names to melt.
#' @param id_cols Columns to keep as identifiers; default everything else.
#' @param units Optional named character vector mapping parameter -> units, since
#'   wide files usually carry units in a header or codebook rather than per cell.
#'   Unmatched parameters get NA units.
#' @return Long tibble with columns: `id_cols...`, `parameter`, `value_raw`,
#'   `units`.
#' @export
melt_wide <- function(df, param_cols, id_cols = setdiff(names(df), param_cols),
                      units = NULL) {
  missing_cols <- setdiff(param_cols, names(df))
  if (length(missing_cols)) {
    stop("param_cols not in data: ", paste(missing_cols, collapse = ", "))
  }
  long <- tidyr::pivot_longer(
    df,
    cols = dplyr::all_of(param_cols),
    names_to = "parameter",
    values_to = "value_raw"
  )
  # Drop empty cells created by the wide layout (not real measurements).
  long <- long[!is.na(long$value_raw) & trimws(long$value_raw) != "", ]
  long$units <- if (!is.null(units)) unname(units[long$parameter]) else NA_character_
  long[, c(id_cols, "parameter", "value_raw", "units")]
}
