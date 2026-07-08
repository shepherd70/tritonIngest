# layout.R
# ---------------------------------------------------------------------------
# Long/wide layout detection and wide -> long reshaping.
#
# A "long/tidy" table has one measurement per row (a parameter column and a
# value column). A "wide" table spreads measured variables across columns. These
# heuristics pick a default; the caller can always override.
# ---------------------------------------------------------------------------

#' Does a character vector look numeric-ish (allowing censored notation)?
#'
#' Used by layout detection: a measured-variable column in a wide file contains
#' numbers and possibly censored entries (`"<DL"`, `">2420"`, `"ND"`, `"TNTC"`).
#'
#' @param x Character vector.
#' @param threshold Minimum fraction of non-missing entries that must parse as a
#'   number or a recognised censored token.
#' @param na_strings Placeholders that mean "not measured" and are excluded from
#'   the denominator alongside `NA` and `""`. Excel exports commonly write `"-"`;
#'   before 0.6.0 such a column scored as *not* value-like and a wide sheet could
#'   lose most of its analyte columns.
#' @return `TRUE`/`FALSE`.
#' @export
is_value_like <- function(x, threshold = 0.8,
                          na_strings = c("-", "--", "n/a", "N/A")) {
  x <- x[!is.na(x)]
  x <- trimws(x)
  x <- x[nzchar(x) & !toupper(x) %in% toupper(as.character(na_strings))]
  if (!length(x)) return(FALSE)
  numeric_ok <- suppressWarnings(!is.na(as.numeric(x)))
  # Reuse the shared vocabularies (ND_TOKENS, OVER_TOKENS) and the censor regex
  # defined in censored.R, so layout detection and value parsing recognise the
  # same tokens and cannot drift (a "NON-DETECT" or ">2420" column is value-like
  # to both).
  cens_ok <- grepl(CENSOR_REGEX, x, perl = TRUE) |
    toupper(x) %in% c(ND_TOKENS, OVER_TOKENS)
  mean(numeric_ok | cens_ok) >= threshold
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
#' @section Transposed tables:
#' A third shape exists in the wild: analytes down the first column and one
#' *sample* per column (a lab's "results matrix"). Its columns are numeric, so
#' this function reports `"wide"` and a caller melting on `value_like_cols` would
#' emit one `parameter` per sample. [looks_transposed()] tests for that shape and
#' [transpose_table()] converts it; `detect_layout()` reports `layout =
#' "transposed"` when the test fires.
#'
#' @param df A data frame (typically read all-text via [read_tabular()]).
#' @param param_names,value_names Character vectors of lowercase column names
#'   that signal a long-format parameter / value column. Matched after
#'   lowercasing and whitespace-trimming the data's names. Override to match a
#'   domain's vocabulary.
#' @param na_strings Placeholders treated as missing by [is_value_like()].
#' @return A list: `layout` (`"long"`/`"wide"`/`"transposed"`), `value_like_cols`,
#'   `reason`.
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
                                          "measurement", "measurements"),
                          na_strings = c("-", "--", "n/a", "N/A")) {
  nms <- trimws(tolower(names(df)))
  param_name_hit <- nms %in% param_names
  value_name_hit <- nms %in% value_names

  value_like <- vapply(df, is_value_like, logical(1), na_strings = na_strings)
  # An id/date column can look numeric; don't count obvious id/date columns.
  idish <- nms %in% c("row", "id", "sample_id", "sampleid", "index") |
    grepl("date|time", nms)
  value_like_cols <- names(df)[value_like & !idish]

  trans <- looks_transposed(df, param_names = param_names, na_strings = na_strings)

  if (any(param_name_hit) && any(value_name_hit)) {
    layout <- "long"
    reason <- "found parameter and value column names"
  } else if (isTRUE(trans$transposed)) {
    layout <- "transposed"
    reason <- trans$reason
  } else if (length(value_like_cols) >= 2) {
    layout <- "wide"
    reason <- paste0(length(value_like_cols), " value-like columns: ",
                     paste(utils::head(value_like_cols, 12), collapse = ", "),
                     if (length(value_like_cols) > 12)
                       paste0(", ... (+", length(value_like_cols) - 12, " more)") else "")
  } else if (any(param_name_hit) || length(value_like_cols) == 1) {
    layout <- "long"
    reason <- "single value-like column"
  } else {
    layout <- "long"
    reason <- "no clear signal; defaulting to long - please confirm"
  }

  list(layout = layout, value_like_cols = value_like_cols, reason = reason)
}

#' Does this table hold analytes down a column and samples across the header?
#'
#' A lab "results matrix" puts one analyte per row and one *sample* per column.
#' Its data columns are numeric, so [detect_layout()] would otherwise call it
#' `"wide"` and a caller melting on `value_like_cols` would produce one
#' `parameter` per sample rather than per analyte.
#'
#' Two independent signals, either of which is enough:
#' \itemize{
#'   \item a `param_names` token (`"analyte"`, `"parameter"`, ...) appears among
#'     the **values** of the first column rather than as a column name; or
#'   \item at least `min_dup_frac` of the header names are duplicates (the same
#'     station or sample point sampled repeatedly), while the first column is not
#'     value-like and carries several distinct labels.
#' }
#' The second signal only fires on a header read with `.name_repair = "minimal"`;
#' a reader that has already made the names unique has destroyed the evidence.
#'
#' @param df A data frame.
#' @param param_names Vocabulary of parameter-column labels (see [detect_layout()]).
#' @param min_labels Minimum distinct non-numeric labels required in column 1.
#' @param min_dup_frac Minimum duplicated fraction of the header names.
#' @param na_strings Placeholders treated as missing.
#' @return A list: `transposed` (lgl), `reason` (chr).
#' @export
looks_transposed <- function(df,
                             param_names = c("parameter", "parameters", "param",
                                             "analyte", "analytes",
                                             "characteristic", "constituent",
                                             "variable", "determinand"),
                             min_labels = 5L, min_dup_frac = 0.3,
                             na_strings = c("-", "--", "n/a", "N/A")) {
  no <- list(transposed = FALSE, reason = "")
  if (!ncol(df) || nrow(df) < 2) return(no)

  first <- trimws(as.character(df[[1]]))
  first <- first[!is.na(first) & nzchar(first)]
  if (!length(first)) return(no)

  if (any(tolower(first) %in% param_names)) {
    return(list(transposed = TRUE,
                reason = paste0("a parameter label ('",
                                first[tolower(first) %in% param_names][1],
                                "') appears as a CELL in column 1, not as a column name; ",
                                "analytes run down the rows and samples across the header")))
  }

  if (is_value_like(df[[1]], na_strings = na_strings)) return(no)
  if (length(unique(first)) < min_labels) return(no)

  nms <- trimws(as.character(names(df)))
  nms <- nms[nzchar(nms)]
  if (length(nms) < 3) return(no)
  dup_frac <- sum(duplicated(nms)) / length(nms)
  if (dup_frac < min_dup_frac) return(no)

  list(transposed = TRUE,
       reason = paste0(round(100 * dup_frac), "% of header names are duplicates and column 1 ",
                       "holds ", length(unique(first)), " distinct non-numeric labels; ",
                       "the header is sample ids, not analytes"))
}

#' Transpose an analyte-by-sample results matrix into a tidy long table.
#'
#' Converts the shape [looks_transposed()] detects. The first `n_label_cols`
#' columns describe each analyte (its name, its units, guideline columns, ...) and
#' the remaining columns are one per sample. `header_rows` names the rows above the
#' analyte block that describe each sample (sample id, date, time, location);
#' each becomes a column of the output.
#'
#' @param df A data frame read all-text with the header **not** promoted
#'   (`read_tabular(col_names = FALSE)`), so the sample-describing rows are data.
#' @param header_rows Named integer vector: output column name -> row index, e.g.
#'   `c(location = 1, lab_id = 2, sample_date = 3, sample_time = 4)`.
#' @param body_rows Integer vector of rows holding analyte results.
#' @param label_cols Named integer vector: output column name -> column index for
#'   the per-analyte label columns, e.g. `c(parameter = 1, units = 2)`.
#' @param sample_cols Integer vector of columns holding sample results.
#' @param na_strings Cell values dropped as "not measured".
#' @return A long tibble: one row per (sample, analyte), with the `header_rows`
#'   and `label_cols` names as columns plus `value_raw`.
#' @export
transpose_table <- function(df, header_rows, body_rows, label_cols, sample_cols,
                            na_strings = c("-", "--", "n/a", "N/A")) {
  stopifnot(is.data.frame(df), length(header_rows) >= 1, length(label_cols) >= 1)
  if (is.null(names(header_rows)) || any(!nzchar(names(header_rows)))) {
    stop("`header_rows` must be a *named* integer vector (output name -> row index).", call. = FALSE)
  }
  if (is.null(names(label_cols)) || any(!nzchar(names(label_cols)))) {
    stop("`label_cols` must be a *named* integer vector (output name -> column index).", call. = FALSE)
  }
  clash <- intersect(c(names(header_rows), names(label_cols)), "value_raw")
  if (length(clash)) stop("`value_raw` is a reserved output name.", call. = FALSE)

  cell <- function(r, cc) trimws(as.character(df[[cc]][r]))
  pieces <- lapply(sample_cols, function(cc) {
    meta <- lapply(header_rows, function(r) rep(cell(r, cc), length(body_rows)))
    labs <- lapply(label_cols, function(lc) trimws(as.character(df[[lc]][body_rows])))
    out <- tibble::as_tibble(c(meta, labs))
    out$value_raw <- trimws(as.character(df[[cc]][body_rows]))
    out
  })
  long <- dplyr::bind_rows(pieces)
  keep <- !is.na(long$value_raw) & nzchar(long$value_raw) &
    !toupper(long$value_raw) %in% toupper(as.character(na_strings))
  long[keep, , drop = FALSE]
}

#' Melt a wide table (variables as columns) to long form.
#'
#' Errors if a retained id column is named `parameter`, `value_raw`, or `units`
#' (the reshape's output names) rather than silently overwriting it.
#'
#' @param df Wide data frame.
#' @param param_cols Character vector of measured-variable column names to melt.
#' @param id_cols Columns to keep as identifiers; default everything else.
#' @param units Optional named character vector mapping parameter -> units, since
#'   wide files usually carry units in a header or codebook rather than per cell.
#'   Unmatched parameters get NA units.
#' @param na_strings Cell values dropped alongside blanks as "not measured".
#'   Excel exports commonly write `"-"`; before 0.6.0 those rows survived the melt
#'   and became `"unparseable result text: '-'"` downstream.
#' @return Long tibble with columns: `id_cols...`, `parameter`, `value_raw`,
#'   `units`.
#' @export
melt_wide <- function(df, param_cols, id_cols = setdiff(names(df), param_cols),
                      units = NULL, na_strings = c("-", "--", "n/a", "N/A")) {
  missing_cols <- setdiff(param_cols, names(df))
  if (length(missing_cols)) {
    stop("param_cols not in data: ", paste(missing_cols, collapse = ", "))
  }
  # The reshape produces fixed output names; if a retained id column already uses
  # one, pivoting/`$units<-` would duplicate or silently clobber it. Fail clearly.
  clash <- intersect(c("parameter", "value_raw", "units"), id_cols)
  if (length(clash)) {
    stop("melt_wide() would overwrite existing column(s) ",
         paste0("'", clash, "'", collapse = ", "),
         " with reshape output of the same name; rename or drop them first ",
         "(reserved output names: parameter, value_raw, units).", call. = FALSE)
  }
  long <- tidyr::pivot_longer(
    df,
    cols = dplyr::all_of(param_cols),
    names_to = "parameter",
    values_to = "value_raw"
  )
  # Drop empty cells created by the wide layout (not real measurements), plus the
  # placeholder markers a spreadsheet uses instead of leaving a cell blank.
  vr <- trimws(long$value_raw)
  long <- long[!is.na(vr) & nzchar(vr) &
                 !toupper(vr) %in% toupper(as.character(na_strings)), ]
  long$units <- if (!is.null(units)) unname(units[long$parameter]) else NA_character_
  long[, c(id_cols, "parameter", "value_raw", "units")]
}
