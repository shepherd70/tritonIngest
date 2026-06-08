# utils.R -- small internal helpers shared across the package.

# NULL/empty/NA-coalescing operator: returns `b` when `a` is NULL, length-0, or
# NA in its first element. Used by the profile readers.
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || is.na(a)[1]) b else a
}
