# cache.R
# ---------------------------------------------------------------------------
# Materialisation cache for the *post-ingestion* canonical object.
#
# Reading a messy lab/field workbook all-as-text and reshaping/validating it is
# expensive; doing it on every report render or dashboard launch is wasteful
# when the source has not changed. This module writes the parsed result to a
# fast-reload cache keyed by a fingerprint of the *source* file, so a stale
# cache (source moved on) auto-invalidates rather than being served silently.
#
# This is NOT an ingestion format: sources still arrive as CSV/XLSX. The cache
# sits one layer downstream of read_tabular()/the contract engine.
#
# Two backends, deliberately different:
#   * "rds"     -- base saveRDS/readRDS. Round-trips ANY R object exactly,
#                  including classes/attributes (e.g. a wqdata tibble keeps its
#                  group_vars attr). R-only, R-version-coupled: an ephemeral,
#                  within-R speed cache.
#   * "parquet" -- arrow::write_parquet/read_parquet (arrow in Suggests). Typed,
#                  compressed, columnar, and readable from R AND Python -- the
#                  right choice for anything shared across tools or archived.
#                  Stores a PLAIN table: S4/attrs/custom classes are dropped, so
#                  the consumer re-wraps (e.g. new_wqdata()) after reading.
#
# The cache directory is supplied by the caller (or via
# options(tritonIngest.cache_dir=)); this package never hardcodes a data path.
# ---------------------------------------------------------------------------

#' Resolve (and optionally create) the cache directory.
#'
#' @param dir Directory to store cache files in. Defaults to
#'   `getOption("tritonIngest.cache_dir")`; errors if neither is set.
#' @param create Logical; create the directory if it does not exist.
#' @return Absolute path to the cache directory.
#' @export
cache_dir <- function(dir = getOption("tritonIngest.cache_dir"),
                      create = TRUE) {
  if (is.null(dir) || !nzchar(dir)) {
    stop("No cache directory: pass `dir=` or set ",
         "options(tritonIngest.cache_dir=).", call. = FALSE)
  }
  if (create && !dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  dir
}

# Fingerprint a source file so the cache can tell whether the source changed.
#   "md5"        -- hash of file *contents* (robust; rereads the file, which for
#                   very large sources partly offsets the cache speedup).
#   "size_mtime" -- size + mtime (cheap; misses an in-place edit that preserves
#                   both, which is rare for lab exports).
# `source` may be several files; each is fingerprinted and the results joined.
.source_fingerprint <- function(source, method = c("md5", "size_mtime")) {
  method <- match.arg(method)
  source <- as.character(source)
  miss <- source[!file.exists(source)]
  if (length(miss)) {
    stop("Source file(s) not found: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  per <- vapply(source, function(f) {
    if (method == "md5") {
      unname(tools::md5sum(normalizePath(f, winslash = "/")))
    } else {
      info <- file.info(f)
      paste0(info$size, "-", as.numeric(info$mtime))
    }
  }, character(1))
  paste(per, collapse = "|")
}

# Sanitise a cache key into a safe file stem (mirrors profiles' .mp_slug).
.cache_slug <- function(key) {
  s <- tolower(trimws(as.character(key)))
  s <- gsub("[^a-z0-9]+", "-", s)
  s <- gsub("^-+|-+$", "", s)
  if (!nzchar(s)) stop("Cache key must contain at least one alphanumeric character.", call. = FALSE)
  s
}

# Derive a stable cache key from a source path when the caller gives none:
# the basename slug plus a short hash of the full normalised path, so two
# different files that share a basename do not collide.
.key_from_source <- function(source) {
  source <- as.character(source)
  stem <- .cache_slug(tools::file_path_sans_ext(basename(source[1])))
  paths <- normalizePath(source, winslash = "/", mustWork = FALSE)
  paste0(stem, "-", substr(.path_hash(paths), 1, 8))
}

# Short md5 of a character vector. tools::md5sum() hashes files, not strings,
# so write the value to a temp file and hash that.
.path_hash <- function(x) {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  writeLines(paste(x, collapse = "|"), tmp)
  unname(tools::md5sum(tmp))
}

# Data file + JSON sidecar paths for a key/format.
.cache_files <- function(key, dir, format) {
  d <- cache_dir(dir, create = TRUE)
  ext <- if (format == "parquet") ".parquet" else ".rds"
  list(
    data = file.path(d, paste0(key, ext)),
    meta = file.path(d, paste0(key, ".cache.json"))
  )
}

#' Write a parsed object to the materialisation cache.
#'
#' Writes the data file plus a JSON sidecar recording the source fingerprint,
#' format, timestamp and shape, so [read_cache()] can later decide whether the
#' cache is still fresh.
#'
#' @param x The object to cache. For `format = "parquet"` it must be a data
#'   frame; any classes/attributes beyond the plain table are dropped (with a
#'   warning) -- use `"rds"` to preserve a classed object exactly.
#' @param source Path(s) to the source file(s) the object was parsed from. Used
#'   to fingerprint the inputs; may be `NULL` to cache without invalidation.
#' @param key Cache key (file stem). Defaults to one derived from `source`.
#' @param dir Cache directory (see [cache_dir()]).
#' @param format `"rds"` (default) or `"parquet"`.
#' @param fingerprint Source-fingerprint method, `"md5"` (default) or
#'   `"size_mtime"` (cheaper for very large sources).
#' @param meta Optional named list of extra provenance to record in the sidecar.
#' @return The path to the written data file (invisibly).
#' @export
write_cache <- function(x, source = NULL, key = NULL,
                        dir = getOption("tritonIngest.cache_dir"),
                        format = c("rds", "parquet"),
                        fingerprint = c("md5", "size_mtime"),
                        meta = list()) {
  format <- match.arg(format)
  fingerprint <- match.arg(fingerprint)
  if (is.null(key)) {
    if (is.null(source)) stop("Provide `key=` or `source=` to name the cache.", call. = FALSE)
    key <- .key_from_source(source)
  }
  key_in <- as.character(key)
  key <- .cache_slug(key)
  paths <- .cache_files(key, dir, format)
  # Warn if this slug was previously written under a different original key: an
  # explicit-key slug collision would otherwise overwrite another cache silently.
  if (file.exists(paths$meta)) {
    prev <- tryCatch(jsonlite::fromJSON(paths$meta)$key_original, error = function(e) NULL)
    if (!is.null(prev) && !identical(as.character(prev), key_in)) {
      warning(sprintf(paste0("Cache key '%s' collides with previously cached ",
                            "'%s' (both slug to '%s'); overwriting."),
                     key_in, prev, key), call. = FALSE)
    }
  }

  if (format == "parquet") {
    if (!is.data.frame(x)) {
      stop("format = 'parquet' requires a data frame; got ", class(x)[1],
           ". Use format = 'rds' for a non-tabular object.", call. = FALSE)
    }
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("format = 'parquet' needs the 'arrow' package (Suggests). ",
           "Install it, or use format = 'rds'.", call. = FALSE)
    }
    extra <- setdiff(class(x), c("tbl_df", "tbl", "data.frame"))
    if (length(extra)) {
      warning("Parquet stores a plain table; dropping class/attributes (",
              paste(extra, collapse = ", "), "). Re-wrap after read_cache().",
              call. = FALSE)
    }
    arrow::write_parquet(as.data.frame(x), paths$data)
  } else {
    saveRDS(x, paths$data)
  }

  fp <- if (is.null(source)) NA_character_ else .source_fingerprint(source, fingerprint)
  payload <- list(
    schema             = "triton-cache/v1",
    key                = key,
    key_original       = key_in,
    source             = if (is.null(source)) NULL else as.character(source),
    fingerprint_method = fingerprint,
    source_fingerprint = fp,
    format             = format,
    created_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    n_row              = if (is.data.frame(x)) nrow(x) else NA_integer_,
    n_col              = if (is.data.frame(x)) ncol(x) else NA_integer_,
    class              = class(x),
    meta               = meta %||% list()
  )
  jsonlite::write_json(payload, paths$meta, auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(paths$data)
}

#' Read from the materialisation cache, if present and still fresh.
#'
#' Returns the cached object when the data file and its sidecar exist and -- when
#' the sidecar recorded a source fingerprint -- the current `source` still matches
#' it. A miss or a stale/changed source returns `NULL` (with a message), so the
#' caller re-parses rather than trusting an out-of-date cache.
#'
#' @param key Cache key. Defaults to one derived from `source`.
#' @param source Path(s) to the current source file(s); compared against the
#'   recorded fingerprint. `NULL` skips the freshness check.
#' @param dir Cache directory (see [cache_dir()]).
#' @param format `"rds"` (default) or `"parquet"`.
#' @return The cached object, or `NULL` on a miss / stale source.
#' @export
read_cache <- function(key = NULL, source = NULL,
                       dir = getOption("tritonIngest.cache_dir"),
                       format = c("rds", "parquet")) {
  format <- match.arg(format)
  if (is.null(key)) {
    if (is.null(source)) stop("Provide `key=` or `source=`.", call. = FALSE)
    key <- .key_from_source(source)
  }
  key <- .cache_slug(key)
  paths <- .cache_files(key, dir, format)
  if (!file.exists(paths$data) || !file.exists(paths$meta)) return(NULL)

  m <- tryCatch(jsonlite::fromJSON(paths$meta), error = function(e) NULL)
  if (is.null(m)) return(NULL)

  # Freshness: if both a source is given now and a fingerprint was recorded,
  # they must match. A vanished source or a changed fingerprint is stale.
  if (!is.null(source) && length(m$source_fingerprint) &&
      !is.na(m$source_fingerprint)) {
    method <- m$fingerprint_method %||% "md5"
    now <- tryCatch(.source_fingerprint(source, method),
                    error = function(e) NA_character_)
    if (is.na(now) || !identical(now, m$source_fingerprint)) {
      message("tritonIngest cache '", key, "' is stale (source changed); re-parsing.")
      return(NULL)
    }
  }

  if (format == "parquet") {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Reading a parquet cache needs the 'arrow' package.", call. = FALSE)
    }
    tibble::as_tibble(arrow::read_parquet(paths$data))
  } else {
    readRDS(paths$data)
  }
}

#' Ingest a source, using the cache when fresh and rebuilding it when not.
#'
#' The standard ingest-with-cache flow: try [read_cache()]; on a miss/stale
#' source, run `parse(source, ...)`, write the result to the cache, and return
#' it. `parse` defaults to [read_tabular()] but is typically a project-specific
#' function that parses *and* validates into the canonical object.
#'
#' @param source Path(s) to the source file(s).
#' @param parse Function called as `parse(source, ...)` on a cache miss; must
#'   return the object to cache. Defaults to [read_tabular()].
#' @param key Cache key. Defaults to one derived from `source`.
#' @param dir Cache directory (see [cache_dir()]).
#' @param format `"rds"` (default) or `"parquet"`.
#' @param fingerprint Source-fingerprint method (see [write_cache()]).
#' @param ... Passed to `parse`.
#' @return The canonical object, from cache or freshly parsed.
#' @export
cached_ingest <- function(source, parse = read_tabular, key = NULL,
                          dir = getOption("tritonIngest.cache_dir"),
                          format = c("rds", "parquet"),
                          fingerprint = c("md5", "size_mtime"), ...) {
  format <- match.arg(format)
  fingerprint <- match.arg(fingerprint)
  hit <- read_cache(key = key, source = source, dir = dir, format = format)
  if (!is.null(hit)) return(hit)
  obj <- parse(source, ...)
  write_cache(obj, source = source, key = key, dir = dir,
              format = format, fingerprint = fingerprint)
  obj
}
