# censored.R
# ---------------------------------------------------------------------------
# Censored (non-detect and over-range) value parsing and simple substitution.
#
# Parse raw result text into (value, censored, censor_direction,
# detection_limit, qualifier) and provide the simple substitution rules
# (1/2 DL, DL, 0). Robust estimators (Kaplan-Meier, ROS) are statistics, not
# ingestion, and stay in the consuming package.
#
# Parsing rules (case-insensitive, whitespace-tolerant):
#   "<0.01", "< 0.01"  -> left-censored,  limit = 0.01
#   ">2420", "> 2420"  -> right-censored, limit = 2420
#   "ND","N.D.","BDL","DNQ","U","non-detect" -> left-censored, limit from the
#       detection-limit column when supplied (NA otherwise, noted)
#   "TNTC"             -> right-censored, limit unknown unless supplied
#   "12.3"             -> detected, value = 12.3
#   "178d", "<10 DLCI", "MBEF <1" -> as above, with `qualifier` capturing the flag
#   "-", "n/a"         -> missing (see `na_strings`)
#   anything else      -> unparseable: value = NA, censored = NA (true unknown)
# ---------------------------------------------------------------------------

#' Non-detect and over-range vocabularies
#'
#' `ND_TOKENS` are bare left-censored markers; `OVER_TOKENS` are bare
#' right-censored markers ("too numerous to count"). Shared with
#' [is_value_like()] so parsing and layout detection cannot drift apart.
#' @keywords internal
#' @noRd
ND_TOKENS   <- c("ND", "N.D.", "BDL", "B.D.L.", "DNQ", "U", "NON-DETECT", "NONDETECT")
OVER_TOKENS <- c("TNTC", "TOO NUMEROUS TO COUNT")

# A real number: digits are mandatory. The previous pattern was
# "[0-9.eE+-]+", a character class, so "<-", "<.", "<e" and "<+-" all matched
# and were reported as clean left-censored values with an NA limit.
.NUM_RE <- "[+-]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?"

# Kept for backward compatibility; now digit-strict.
ND_LT_REGEX     <- paste0("^<\\s*", .NUM_RE, "$")
ND_GT_REGEX     <- paste0("^>\\s*", .NUM_RE, "$")
#' @keywords internal
#' @noRd
CENSOR_REGEX    <- paste0("^[<>]\\s*", .NUM_RE, "$")

# Full form: optional leading flag, optional censor operator, a number, optional
# trailing flag. Captures "178d", ">45.5c", "114c,RRR", "<10 DLCI", "MBEF <1".
#
# The trailing flag must start with a letter (or be a run of dashes) and contain
# no whitespace. That is what stops a permit range like "5.4 to 8.7" or a narrative
# cell like "50% survival" from being read as the number 5.4 / 50 with the rest
# discarded as a "qualifier" -- both must stay unparseable.
.QUAL_TAIL <- "(?:[A-Za-z][A-Za-z0-9,._+-]*|-{2,})?"
.CENSOR_FULL <- paste0(
  "^(?:([A-Za-z][A-Za-z0-9._]*)[ \t]+)?",   # 1 leading qualifier
  "([<>])?[ \t]*",                          # 2 censor operator
  "(", .NUM_RE, ")",                        # 3 the number
  "[ \t]*(", .QUAL_TAIL, ")$"               # 4 trailing qualifier
)
# Same shape, no qualifiers: keeps the four capture groups so one parser serves both.
.CENSOR_STRICT <- paste0("^()([<>])?[ \t]*(", .NUM_RE, ")()$")

#' Parse raw result text into value / censoring / limit / qualifier.
#'
#' Recognises left-censored (`"<x"`, `"ND"`), right-censored (`">x"`, `"TNTC"`)
#' and detected values, and separates any laboratory qualifier flag from the
#' number it decorates (`"178d"` -> value 178, qualifier `"d"`).
#'
#' @section Two limit columns, on purpose:
#' `detection_limit` keeps its original meaning -- the detection/reporting limit
#' below which a result was not detected. It is populated for left-censored rows
#' and is **`NA` for right-censored ones**: a `">2420"` result has no detection
#' limit, it has a quantitation ceiling. That ceiling lives in `censor_limit`,
#' which carries the numeric bound for *either* direction.
#'
#' The split is what makes the default safe. A caller that does not yet know about
#' right-censoring calls `apply_substitution(value, censored, detection_limit)`;
#' the right-censored rows have `detection_limit = NA`, so they drop to `NA`
#' rather than being substituted as `fraction * ceiling` -- which would fabricate
#' a number *below* the true value. Pass `censor_direction` and `censor_limit` to
#' use them properly.
#'
#' @param value_raw Character vector of raw results as read from file.
#' @param detection_limit Optional numeric vector (recycled if length 1) from a
#'   separate DL/RL column; used for bare tokens (`"ND"`) and checked for
#'   consistency against `"<DL"` notation.
#' @param na_strings Values (compared case-insensitively after trimming) that mean
#'   "not measured" rather than a result. Excel exports commonly write `"-"`.
#' @param nd_tokens,over_tokens Bare left- / right-censored markers.
#' @param qualifiers Extract leading/trailing laboratory flags from an otherwise
#'   numeric cell. `FALSE` restores the strict behaviour in which `"178d"` is
#'   unparseable.
#' @return A tibble: `value` (dbl, NA where censored/unparseable), `censored`
#'   (lgl: TRUE when the true value is not directly observed, in either
#'   direction; NA where unparseable), `censor_direction`
#'   (`"none"`/`"left"`/`"right"`, NA where unparseable), `detection_limit` (dbl,
#'   left-censored rows only), `censor_limit` (dbl, the bound in either
#'   direction), `qualifier` (chr, NA when none), `parse_note` (chr, NA when
#'   clean).
#' @export
parse_censored <- function(value_raw, detection_limit = NULL,
                           na_strings = c("-", "--", "n/a", "N/A"),
                           nd_tokens = ND_TOKENS, over_tokens = OVER_TOKENS,
                           qualifiers = TRUE) {
  raw <- trimws(as.character(value_raw))
  n <- length(raw)
  if (!is.null(detection_limit) && !length(detection_limit) %in% c(1L, n)) {
    stop("`detection_limit` length (", length(detection_limit),
         ") must be 1 or match `value_raw` (", n, ").", call. = FALSE)
  }

  dl_col <- if (is.null(detection_limit)) {
    rep(NA_real_, n)
  } else {
    suppressWarnings(as.numeric(rep(detection_limit, length.out = n)))
  }

  value     <- rep(NA_real_, n)
  censored  <- rep(NA, n)             # logical NA = unparseable/unknown
  direction <- rep(NA_character_, n)
  dl_out    <- dl_col                 # detection limit (left-censored only)
  cl_out    <- rep(NA_real_, n)       # censoring bound, either direction
  qual      <- rep(NA_character_, n)
  note      <- rep(NA_character_, n)

  up <- toupper(raw)
  empty <- is.na(raw) | raw == "" | up %in% toupper(as.character(na_strings))
  note[empty] <- "missing"

  # Bare tokens ---------------------------------------------------------------
  tok_nd <- !empty & up %in% toupper(nd_tokens)
  censored[tok_nd] <- TRUE
  direction[tok_nd] <- "left"
  cl_out[tok_nd] <- dl_col[tok_nd]
  note[tok_nd & is.na(dl_out)] <- "non-detect token without a detection limit"

  # A right-censored result has no detection limit; a DL column value describes
  # the low end of the range and must not be mistaken for the ceiling.
  tok_gt <- !empty & up %in% toupper(over_tokens)
  censored[tok_gt] <- TRUE
  direction[tok_gt] <- "right"
  dl_out[tok_gt] <- NA_real_
  note[tok_gt] <- "over-range token without a quantitation limit"

  # Numeric forms, with optional operator and qualifier ------------------------
  todo <- which(!empty & !tok_nd & !tok_gt)
  if (length(todo)) {
    pat <- if (isTRUE(qualifiers)) .CENSOR_FULL else .CENSOR_STRICT
    hit <- grepl(pat, raw[todo], perl = TRUE)
    idx <- todo[hit]
    if (length(idx)) {
      m <- regmatches(raw[idx], regexec(pat, raw[idx], perl = TRUE))
      lead <- vapply(m, function(g) g[2], character(1))
      op   <- vapply(m, function(g) g[3], character(1))
      num  <- suppressWarnings(as.numeric(vapply(m, function(g) g[4], character(1))))
      tail <- vapply(m, function(g) g[5], character(1))

      flags <- trimws(paste(lead, tail))
      flags[!nzchar(flags)] <- NA_character_
      qual[idx] <- flags

      is_lt <- op == "<"
      is_gt <- op == ">"
      is_pl <- !nzchar(op)

      censored[idx[is_lt]]  <- TRUE; direction[idx[is_lt]] <- "left"
      dl_out[idx[is_lt]]    <- num[is_lt]
      cl_out[idx[is_lt]]    <- num[is_lt]
      # ">x": the bound is a ceiling, not a detection limit. Leaving
      # detection_limit NA is what keeps a direction-blind apply_substitution()
      # from returning fraction * ceiling.
      censored[idx[is_gt]]  <- TRUE; direction[idx[is_gt]] <- "right"
      dl_out[idx[is_gt]]    <- NA_real_
      cl_out[idx[is_gt]]    <- num[is_gt]
      censored[idx[is_pl]]  <- FALSE; direction[idx[is_pl]] <- "none"
      value[idx[is_pl]]     <- num[is_pl]

      # Flag disagreement with a supplied DL column (parsed "<X" wins).
      lt_abs <- idx[is_lt]
      disagree <- !is.na(dl_col[lt_abs]) &
        abs(dl_col[lt_abs] - dl_out[lt_abs]) > .Machine$double.eps^0.5
      note[lt_abs[disagree]] <- "DL in text differs from detection-limit column; text used"
    }
    bad <- todo[!hit]
    note[bad] <- paste0("unparseable result text: '", raw[bad], "'")
  }

  tibble::tibble(value = value, censored = censored,
                 censor_direction = direction,
                 detection_limit = dl_out, censor_limit = cl_out,
                 qualifier = qual, parse_note = note)
}

#' Apply a simple substitution rule to censored values.
#'
#' Returns a numeric vector where censored entries are replaced by a working
#' value; detected entries pass through unchanged. Transparent and widely used,
#' but can bias variance estimates.
#'
#' Left-censored entries become `fraction * detection_limit`. Right-censored
#' entries become `censor_limit` itself -- the true value is known only to exceed
#' the ceiling, so substituting a fraction of it would understate the result.
#'
#' @section Safe by default:
#' When `censor_direction` is `NULL` every censored entry is treated as
#' **left**-censored, which reproduces the pre-0.6.0 behaviour. That is safe
#' because [parse_censored()] leaves `detection_limit` as `NA` for right-censored
#' rows: a caller that does not pass `censor_direction` gets `NA` for them, not a
#' fabricated `fraction * ceiling`. Pass both `censor_direction` and
#' `censor_limit` -- or, more simply, pass the whole [parse_censored()] tibble to
#' [working_values()] -- to substitute right-censored results properly.
#'
#' @param value Numeric vector (NA where censored).
#' @param censored Logical vector, the same length as `value`.
#' @param detection_limit Numeric vector of detection limits (length 1, recycled,
#'   or the same length as `value`).
#' @param fraction Substitution fraction for left-censored values: 0.5 (default,
#'   = 1/2 DL), 1 (DL), or 0.
#' @param censor_direction Optional character vector of `"none"`/`"left"`/
#'   `"right"`, the same length as `value`.
#' @param censor_limit Optional numeric vector of censoring bounds, used for
#'   right-censored entries. Required whenever `censor_direction` names any
#'   `"right"` entry.
#' @return Numeric vector with censored entries substituted (NA where the limit
#'   itself is unknown).
#' @export
apply_substitution <- function(value, censored, detection_limit, fraction = 0.5,
                               censor_direction = NULL, censor_limit = NULL) {
  if (!fraction %in% c(0, 0.5, 1)) {
    stop("fraction must be one of 0, 0.5, 1 (got ", fraction, ")")
  }
  n <- length(value)
  if (length(censored) != n) {
    stop("`censored` length (", length(censored), ") must match `value` (", n,
         ").", call. = FALSE)
  }
  if (!length(detection_limit) %in% c(1L, n)) {
    stop("`detection_limit` length (", length(detection_limit),
         ") must be 1 or match `value` (", n, ").", call. = FALSE)
  }
  if (!is.null(censor_direction) && length(censor_direction) != n) {
    stop("`censor_direction` length (", length(censor_direction),
         ") must match `value` (", n, ").", call. = FALSE)
  }
  if (!is.null(censor_limit) && !length(censor_limit) %in% c(1L, n)) {
    stop("`censor_limit` length (", length(censor_limit),
         ") must be 1 or match `value` (", n, ").", call. = FALSE)
  }
  dl  <- if (length(detection_limit) == 1L) rep(detection_limit, n) else detection_limit
  out <- value
  cens <- !is.na(censored) & censored

  if (is.null(censor_direction)) {
    out[cens] <- fraction * dl[cens]
    return(out)
  }

  left  <- cens & !is.na(censor_direction) & censor_direction == "left"
  right <- cens & !is.na(censor_direction) & censor_direction == "right"
  if (any(right) && is.null(censor_limit)) {
    stop("`censor_direction` names ", sum(right), " right-censored value(s) but ",
         "`censor_limit` was not supplied. A right-censored result's bound is a ",
         "ceiling, not a detection limit; pass parse_censored()$censor_limit.",
         call. = FALSE)
  }
  cl <- if (is.null(censor_limit)) dl
        else if (length(censor_limit) == 1L) rep(censor_limit, n) else censor_limit
  out[left]  <- fraction * dl[left]
  out[right] <- cl[right]
  out
}

#' Working numeric values for a censoring method.
#'
#' A single censoring "switch" for code that needs a plain numeric vector. Maps
#' (value, censored, detection_limit) to working values under the chosen
#' non-detect handling. Only substitution is supported here; robust group-level
#' estimators (KM/ROS) live in the consuming package.
#'
#' Pass the whole [parse_censored()] tibble as `value` to handle both censoring
#' directions correctly with no further arguments:
#' `working_values(parse_censored(x))`. The vector form is kept for callers that
#' carry the columns separately; without `censor_direction` it treats every
#' censored entry as left-censored (see [apply_substitution()]).
#'
#' @param value Numeric vector (NA where censored), **or** a tibble returned by
#'   [parse_censored()], in which case the remaining columns are taken from it.
#' @param censored Logical vector (NA = unparseable).
#' @param detection_limit Numeric vector of detection limits.
#' @param method Censoring method; currently only `"substitution"`.
#' @param fraction Substitution fraction (0, 0.5, or 1).
#' @param censor_direction Optional `"none"`/`"left"`/`"right"` vector; see
#'   [apply_substitution()].
#' @param censor_limit Optional numeric vector of censoring bounds; see
#'   [apply_substitution()].
#' @return Numeric vector with censored entries handled per method.
#' @export
working_values <- function(value, censored, detection_limit,
                           method = c("substitution"), fraction = 0.5,
                           censor_direction = NULL, censor_limit = NULL) {
  method <- match.arg(method)
  if (is.data.frame(value)) {
    need <- c("value", "censored", "detection_limit")
    if (!all(need %in% names(value))) {
      stop("A data-frame `value` must be a parse_censored() result; missing: ",
           paste(setdiff(need, names(value)), collapse = ", "), call. = FALSE)
    }
    p <- value
    # NB: this package's %||% is NA-coalescing, so it would collapse a column
    # whose first element is NA to the fallback. Test for presence explicitly.
    col <- function(nm) if (nm %in% names(p)) p[[nm]] else NULL
    censored         <- p$censored
    detection_limit  <- p$detection_limit
    censor_direction <- col("censor_direction")
    censor_limit     <- col("censor_limit")
    value            <- p$value
  }
  switch(method,
    substitution = apply_substitution(value, censored, detection_limit,
                                      fraction = fraction,
                                      censor_direction = censor_direction,
                                      censor_limit = censor_limit)
  )
}
