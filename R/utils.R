# utils.R -- small internal helpers shared across the package.

# NULL/empty/NA-coalescing operator: returns `b` when `a` is NULL, length-0, or
# NA in its first element. NOTE: the NA-coalescing part DIVERGES from base R's
# `%||%` (R >= 4.4) and rlang's, which are NULL-only. It is kept because the
# declared floor R (>= 4.2) lacks base `%||%`; on R >= 4.4 it deliberately
# shadows base with the broader NA semantics the profile readers depend on.
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || is.na(a)[1]) b else a
}

# `modified` is a column referenced via dplyr NSE in list_mapping_profiles();
# declare it so R CMD check does not flag it as an undefined global variable.
utils::globalVariables("modified")
