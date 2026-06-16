# utils.R -- small internal helpers shared across the package.

# NULL/empty/NA-coalescing operator: returns `b` when `a` is NULL, length-0, or
# NA in its first element. Used by the profile readers.
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || is.na(a)[1]) b else a
}

# `modified` is a column referenced via dplyr NSE in list_mapping_profiles();
# declare it so R CMD check does not flag it as an undefined global variable.
utils::globalVariables("modified")
