# units.R
# ---------------------------------------------------------------------------
# Unit reconciliation for mass-concentration values.
# ---------------------------------------------------------------------------

#' Convert mass-concentration or mass-fraction values between common units.
#'
#' Handles two ladders independently: **mass/volume** (g/L, mg/L, ug/L, ng/L)
#' and **mass/mass** (g/kg, mg/kg, ug/kg, ng/kg, mg/g, ug/g, ng/g, the latter
#' being the tissue/sediment units). Conversion stays within a ladder --
#' mass/volume and mass/mass are not interconvertible without a density, so a
#' cross-ladder request returns `NA`. The micro prefix is accepted as either the
#' micro sign (U+00B5, `"\u00b5g/L"`) or Greek small mu (U+03BC, common from
#' instrument exports); both fold to the same unit.
#'
#' Returns the value unchanged when units already match (case/space-insensitive).
#' When a non-identity conversion cannot be resolved -- an unknown unit or a
#' cross-ladder pair -- the result is `NA` *and a warning is emitted*, so an
#' unsupported unit class is distinguishable from a value that was simply
#' missing (both would otherwise be a bare `NA`).
#'
#' @param value Numeric vector.
#' @param from Character vector of source units (recycled to `length(value)`).
#' @param to Single target unit.
#' @return Numeric vector of converted values (`NA` where not convertible).
#' @export
convert_units <- function(value, from, to) {
  # Normalise a unit label: lowercase, fold Greek mu (U+03BC) onto the micro
  # sign (U+00B5) so the two visually identical prefixes match one table entry,
  # then drop whitespace. Unicode escapes keep this source pure ASCII (R CMD
  # check --as-cran flags non-ASCII characters in code files).
  norm <- function(u) {
    u <- tolower(ifelse(is.na(u), "", u))
    u <- gsub("\u03bc", "\u00b5", u)
    gsub("\\s+", "", u)
  }
  # Each ladder holds factors to its own base; conversion is only defined within
  # one ladder. Bases: mg/L (mass/volume) and mg/kg = ppm (mass/mass).
  ladders <- list(
    c("g/l" = 1e3, "mg/l" = 1, "ug/l" = 1e-3, "\u00b5g/l" = 1e-3, "ng/l" = 1e-6),
    c("g/kg" = 1e3, "mg/kg" = 1, "ug/kg" = 1e-3, "\u00b5g/kg" = 1e-3,
      "ng/kg" = 1e-6, "mg/g" = 1e3, "ug/g" = 1, "\u00b5g/g" = 1, "ng/g" = 1e-3)
  )
  fac <- unlist(ladders)                                   # unit -> factor
  lad <- rep(seq_along(ladders), lengths(ladders))         # unit -> ladder id
  names(lad) <- names(fac)

  n <- length(value)
  f <- norm(rep(from, length.out = n))
  t <- norm(to)
  out <- rep(NA_real_, n)
  same <- f == t
  out[same] <- value[same]
  if (t %in% names(fac)) {
    conv <- !same & (f %in% names(fac)) & (lad[f] == lad[[t]])
    conv[is.na(conv)] <- FALSE
    out[conv] <- value[conv] * fac[f[conv]] / fac[[t]]
  }
  # Signal a real but unresolved conversion (non-identity, value present, both
  # units given) rather than letting it masquerade as a missing value.
  unresolved <- !same & is.na(out) & !is.na(value) & nzchar(f) & nzchar(t)
  if (any(unresolved)) {
    bad <- unique(f[unresolved])
    warning("convert_units(): cannot convert ",
            paste0("'", bad, "'", collapse = ", "), " to '", to,
            "' (unknown unit or incompatible class, e.g. mass/volume vs ",
            "mass/mass); returned NA.", call. = FALSE)
  }
  out
}
