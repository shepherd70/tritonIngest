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

# Recursively canonicalise common R configuration objects before hashing. Named
# containers are sorted; vector order is preserved because header/source order is
# semantically meaningful.
.canonicalize <- function(x) {
  if (is.data.frame(x)) {
    return(lapply(x[sort(names(x))], .canonicalize))
  }
  if (is.list(x)) {
    if (!is.null(names(x))) x <- x[order(names(x))]
    return(lapply(x, .canonicalize))
  }
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  if (inherits(x, "POSIXt")) return(format(x, "%Y-%m-%dT%H:%M:%OS6%z", tz = "UTC"))
  if (is.factor(x)) return(as.character(x))
  if (is.environment(x) || is.function(x) || inherits(x, "externalptr")) {
    stop("Fingerprint context must contain only serializable data, not ",
         class(x)[1], ".", call. = FALSE)
  }
  x
}

.object_fingerprint <- function(x) {
  text <- jsonlite::toJSON(.canonicalize(x), auto_unbox = TRUE, null = "null",
                           na = "null", digits = NA, POSIXt = "ISO8601")
  digest::digest(text, algo = "sha256", serialize = FALSE)
}

.file_sha256 <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

.atomic_write <- function(path, writer) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(paste0(basename(path), ".tmp-"), tmpdir = dirname(path))
  on.exit(unlink(tmp, force = TRUE), add = TRUE)
  writer(tmp)
  if (file.exists(path)) unlink(path, force = TRUE)
  if (!file.rename(tmp, path)) {
    stop("Could not atomically move temporary file into place: ", path,
         call. = FALSE)
  }
  invisible(path)
}

.with_file_lock <- function(path, code, timeout = 30, stale_after = 300) {
  lock <- paste0(path, ".lock")
  started <- Sys.time()
  repeat {
    if (dir.create(lock, recursive = FALSE, showWarnings = FALSE)) break
    info <- file.info(lock)
    if (!is.na(info$mtime) && as.numeric(difftime(Sys.time(), info$mtime,
                                                  units = "secs")) > stale_after) {
      unlink(lock, recursive = TRUE, force = TRUE)
      next
    }
    if (as.numeric(difftime(Sys.time(), started, units = "secs")) >= timeout) {
      stop("Timed out waiting for cache lock: ", lock, call. = FALSE)
    }
    Sys.sleep(0.05)
  }
  on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  force(code)
}
