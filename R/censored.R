# censored.R
# ---------------------------------------------------------------------------
# Non-detect (left-censored) value parsing and simple substitution.
#
# Parse raw result text into (value, censored, detection_limit) and provide the
# simple substitution rules (1/2 DL, DL, 0). Robust estimators (Kaplan-Meier,
# ROS) are statistics, not ingestion, and stay in the consuming package.
#
# Parsing rules (case-insensitive, whitespace-tolerant):
#   "<0.01", "< 0.01"  -> censored, DL = 0.01
#   "ND","N.D.","BDL","DNQ","U","non-detect" -> censored, DL from the detection-
#       limit column when supplied (NA otherwise, noted)
#   "12.3"             -> detected, value = 12.3
#   anything else      -> unparseable: value = NA, censored = NA (true unknown)
# ---------------------------------------------------------------------------

ND_TOKENS <- c("ND", "N.D.", "BDL", "B.D.L.", "DNQ", "U", "NON-DETECT", "NONDETECT")

#' Parse raw result text into value / censored / detection_limit.
#'
#' @param value_raw Character vector of raw results as read from file.
#' @param detection_limit Optional numeric vector (recycled if length 1) from a
#'   separate DL/RL column; used for token non-detects (`"ND"`) and checked for
#'   consistency against `"<DL"` notation.
#' @return A tibble: `value` (dbl, NA where censored/unparseable), `censored`
#'   (lgl, NA where unparseable), `detection_limit` (dbl), `parse_note` (chr, NA
#'   when clean).
#' @export
parse_censored <- function(value_raw, detection_limit = NULL) {
  raw <- trimws(as.character(value_raw))
  n <- length(raw)

  dl_col <- if (is.null(detection_limit)) {
    rep(NA_real_, n)
  } else {
    suppressWarnings(as.numeric(rep(detection_limit, length.out = n)))
  }

  value    <- rep(NA_real_, n)
  censored <- rep(NA, n)            # logical NA = unparseable/unknown
  dl_out   <- dl_col
  note     <- rep(NA_character_, n)

  empty <- is.na(raw) | raw == ""
  censored[empty] <- NA
  note[empty] <- "missing"

  # "<DL" notation ------------------------------------------------------------
  lt <- grepl("^<\\s*[0-9.eE+-]+$", raw)
  lt_dl <- suppressWarnings(as.numeric(sub("^<\\s*", "", raw[lt])))
  censored[lt] <- TRUE
  dl_out[lt] <- lt_dl
  # Flag disagreement with a supplied DL column (parsed "<X" wins).
  disagree <- lt & !is.na(dl_col) & abs(dl_col - dl_out) > .Machine$double.eps^0.5
  note[disagree] <- "DL in text differs from detection-limit column; text used"

  # Token non-detects ("ND", "BDL", ...) --------------------------------------
  tok <- !empty & !lt & toupper(raw) %in% ND_TOKENS
  censored[tok] <- TRUE
  note[tok & is.na(dl_out)] <- "non-detect token without a detection limit"

  # Plain numerics -------------------------------------------------------------
  num <- suppressWarnings(as.numeric(raw))
  plain <- !empty & !lt & !tok & !is.na(num)
  value[plain] <- num[plain]
  censored[plain] <- FALSE

  # Anything left is unparseable ----------------------------------------------
  bad <- !empty & !lt & !tok & !plain
  note[bad] <- paste0("unparseable result text: '", raw[bad], "'")

  tibble::tibble(value = value, censored = censored,
                 detection_limit = dl_out, parse_note = note)
}

#' Apply a simple substitution rule to censored values.
#'
#' Returns a numeric vector where censored entries are replaced by
#' `fraction * detection_limit`; detected entries pass through unchanged.
#' Transparent and widely used, but can bias variance estimates.
#'
#' @param value Numeric vector (NA where censored).
#' @param censored Logical vector.
#' @param detection_limit Numeric vector of DLs.
#' @param fraction Substitution fraction: 0.5 (default, = 1/2 DL), 1 (DL), or 0.
#' @return Numeric vector with censored entries substituted (NA where the DL
#'   itself is unknown).
#' @export
apply_substitution <- function(value, censored, detection_limit, fraction = 0.5) {
  if (!fraction %in% c(0, 0.5, 1)) {
    stop("fraction must be one of 0, 0.5, 1 (got ", fraction, ")")
  }
  out <- value
  idx <- !is.na(censored) & censored
  out[idx] <- fraction * detection_limit[idx]
  out
}

#' Working numeric values for a censoring method.
#'
#' A single censoring "switch" for code that needs a plain numeric vector. Maps
#' (value, censored, detection_limit) to working values under the chosen
#' non-detect handling. Only substitution is supported here; robust group-level
#' estimators (KM/ROS) live in the consuming package.
#'
#' @param value Numeric vector (NA where censored).
#' @param censored Logical vector (NA = unparseable).
#' @param detection_limit Numeric vector of DLs.
#' @param method Censoring method; currently only `"substitution"`.
#' @param fraction Substitution fraction (0, 0.5, or 1).
#' @return Numeric vector with censored entries handled per method.
#' @export
working_values <- function(value, censored, detection_limit,
                           method = c("substitution"), fraction = 0.5) {
  method <- match.arg(method)
  switch(method,
    substitution = apply_substitution(value, censored, detection_limit,
                                      fraction = fraction)
  )
}
