# units.R
# ---------------------------------------------------------------------------
# Unit reconciliation for mass-concentration values.
# ---------------------------------------------------------------------------

#' Convert mass-concentration values between common units.
#'
#' Handles the concentration ladder (g/L, mg/L, ug/L, ng/L); returns the value
#' unchanged when units already match (case/space-insensitive) and `NA` when the
#' conversion is not defined (so the caller can treat a mismatch as
#' indeterminate rather than silently comparing incompatible units).
#'
#' @param value Numeric vector.
#' @param from Character vector of source units (recycled to `length(value)`).
#' @param to Single target unit.
#' @return Numeric vector of converted values (`NA` where not convertible).
#' @export
convert_units <- function(value, from, to) {
  norm <- function(u) gsub("\\s+", "", tolower(ifelse(is.na(u), "", u)))
  # Factors to a common base (mg/L).
  fac <- c("g/l" = 1e3, "mg/l" = 1, "ug/l" = 1e-3, "µg/l" = 1e-3,
           "ng/l" = 1e-6)
  f <- norm(rep(from, length.out = length(value)))
  t <- norm(to)
  out <- rep(NA_real_, length(value))
  same <- f == t
  out[same] <- value[same]
  if (t %in% names(fac)) {
    conv <- !same & f %in% names(fac)
    out[conv] <- value[conv] * fac[f[conv]] / fac[[t]]
  }
  out
}
