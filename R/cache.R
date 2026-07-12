# cache.R
# Transformation-aware materialisation cache for canonical post-ingestion objects.

#' Resolve the cache directory
#'
#' @param dir Directory to store cache files in.
#' @param create Create it when missing.
#' @return Normalized absolute path.
#' @export
cache_dir <- function(dir = getOption("tritonIngest.cache_dir"), create = TRUE) {
  if (is.null(dir) || length(dir) != 1L || is.na(dir) || !nzchar(dir)) {
    stop("No cache directory: pass `dir=` or set options(tritonIngest.cache_dir=).",
         call. = FALSE)
  }
  if (create && !dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir, winslash = "/", mustWork = FALSE)
}

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

.cache_slug <- function(key) {
  if (length(key) != 1L || is.na(key)) stop("Cache key must be one string.", call. = FALSE)
  s <- tolower(trimws(as.character(key)))
  s <- gsub("[^a-z0-9]+", "-", s)
  s <- gsub("^-+|-+$", "", s)
  if (!nzchar(s)) stop("Cache key must contain an alphanumeric character.", call. = FALSE)
  s
}

.path_hash <- function(x) .object_fingerprint(as.character(x))

.key_from_source <- function(source) {
  source <- as.character(source)
  if (!length(source)) stop("At least one source is required.", call. = FALSE)
  stem <- .cache_slug(tools::file_path_sans_ext(basename(source[1])))
  paths <- normalizePath(source, winslash = "/", mustWork = FALSE)
  paste0(stem, "-", substr(.path_hash(paths), 1, 8))
}

.cache_files <- function(key, dir, format) {
  d <- cache_dir(dir, create = TRUE)
  ext <- if (format == "parquet") ".parquet" else ".rds"
  list(
    data = file.path(d, paste0(key, ext)),
    meta = file.path(d, paste0(key, ".", format, ".cache.json")),
    legacy_meta = file.path(d, paste0(key, ".cache.json"))
  )
}

.transform_fingerprint <- function(context) {
  if (is.null(context)) return(NA_character_)
  context <- .validate_transform_context(context)
  .object_fingerprint(list(context = context, tritonIngest = .package_version()))
}

.write_cache_data <- function(x, path, format) {
  .atomic_write(path, function(tmp) {
    if (format == "parquet") {
      if (!is.data.frame(x)) {
        stop("format = 'parquet' requires a data frame; use RDS otherwise.",
             call. = FALSE)
      }
      if (!requireNamespace("arrow", quietly = TRUE)) {
        stop("format = 'parquet' needs the 'arrow' package.", call. = FALSE)
      }
      extra <- setdiff(class(x), c("spec_tbl_df", "tbl_df", "tbl", "data.frame"))
      if (length(extra)) {
        warning("Parquet stores a plain table; dropping class/attributes (",
                paste(extra, collapse = ", "), ").", call. = FALSE)
      }
      arrow::write_parquet(as.data.frame(x), tmp)
    } else {
      saveRDS(x, tmp)
    }
  })
}

#' Write an object to the transformation-aware cache
#'
#' @param x Object to cache; parquet requires a data frame.
#' @param source Source file path(s), or `NULL` for a provenance-only artifact.
#' @param key Cache key; derived from `source` when omitted.
#' @param dir Cache directory.
#' @param format `"rds"` or `"parquet"`.
#' @param fingerprint `"md5"` or `"size_mtime"` source fingerprint.
#' @param meta Additional metadata.
#' @param transform_context Optional named transformation identity. Cache reads
#'   must supply the same context when one is recorded.
#' @return Data path, invisibly.
#' @export
write_cache <- function(x, source = NULL, key = NULL,
                        dir = getOption("tritonIngest.cache_dir"),
                        format = c("rds", "parquet"),
                        fingerprint = c("md5", "size_mtime"),
                        meta = list(), transform_context = NULL) {
  format <- match.arg(format)
  fingerprint <- match.arg(fingerprint)
  if (is.null(key)) {
    if (is.null(source)) stop("Provide `key=` or `source=` to name the cache.", call. = FALSE)
    key <- .key_from_source(source)
  }
  key_original <- as.character(key)
  key <- .cache_slug(key)
  paths <- .cache_files(key, dir, format)
  context <- .validate_transform_context(transform_context, required = FALSE)

  .with_file_lock(paths$meta, {
    if (file.exists(paths$meta)) {
      previous <- tryCatch(jsonlite::fromJSON(paths$meta)$key_original,
                           error = function(e) NULL)
      if (!is.null(previous) && !identical(as.character(previous), key_original)) {
        stop(sprintf("Cache key '%s' collides with '%s' (both slug to '%s').",
                     key_original, previous, key), call. = FALSE)
      }
    }
    .write_cache_data(x, paths$data, format)
    source_paths <- if (is.null(source)) NULL else
      normalizePath(as.character(source), winslash = "/", mustWork = TRUE)
    payload <- list(
      schema = "triton-cache/v2",
      key = key,
      key_original = key_original,
      format = format,
      artifact_sha256 = .file_sha256(paths$data),
      source = source_paths,
      fingerprint_method = fingerprint,
      source_fingerprint = if (is.null(source)) NA_character_ else
        .source_fingerprint(source, fingerprint),
      transform_fingerprint = .transform_fingerprint(context),
      transform_context = context,
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      tritonIngest_version = .package_version(),
      n_row = if (is.data.frame(x)) nrow(x) else NA_integer_,
      n_col = if (is.data.frame(x)) ncol(x) else NA_integer_,
      class = class(x),
      meta = meta %||% list()
    )
    .atomic_write(paths$meta, function(tmp) {
      jsonlite::write_json(payload, tmp, auto_unbox = TRUE, pretty = TRUE,
                           null = "null", na = "null")
    })
  })
  invisible(paths$data)
}

.cache_miss <- function(key, reason) {
  message("tritonIngest cache '", key, "' miss (", reason, "); re-parsing.")
  NULL
}

#' Read a fresh, verified cache entry
#'
#' @param key Cache key, derived from `source` when omitted.
#' @param source Current source path(s).
#' @param dir Cache directory.
#' @param format `"rds"` or `"parquet"`.
#' @param transform_context Transformation identity used when the entry was written.
#' @return Cached object or `NULL` on any miss/mismatch.
#' @export
read_cache <- function(key = NULL, source = NULL,
                       dir = getOption("tritonIngest.cache_dir"),
                       format = c("rds", "parquet"),
                       transform_context = NULL) {
  format <- match.arg(format)
  if (is.null(key)) {
    if (is.null(source)) stop("Provide `key=` or `source=`.", call. = FALSE)
    key <- .key_from_source(source)
  }
  key <- .cache_slug(key)
  paths <- .cache_files(key, dir, format)
  if (!file.exists(paths$data) || !file.exists(paths$meta)) {
    if (file.exists(paths$legacy_meta)) {
      return(.cache_miss(key, "legacy triton-cache/v1 manifests are never reused"))
    }
    return(NULL)
  }
  m <- tryCatch(jsonlite::fromJSON(paths$meta, simplifyVector = TRUE),
                error = function(e) NULL)
  if (is.null(m) || !identical(m$schema, "triton-cache/v2")) {
    return(.cache_miss(key, "invalid or unsupported manifest"))
  }
  if (!identical(as.character(m$key), key) || !identical(as.character(m$format), format)) {
    return(.cache_miss(key, "manifest key/backend mismatch"))
  }
  if (!identical(.file_sha256(paths$data), as.character(m$artifact_sha256))) {
    return(.cache_miss(key, "artifact checksum mismatch"))
  }
  if (!is.null(source) && !is.null(m$source_fingerprint) &&
      length(m$source_fingerprint) && !is.na(m$source_fingerprint)) {
    now <- tryCatch(.source_fingerprint(source, m$fingerprint_method %||% "md5"),
                    error = function(e) NA_character_)
    if (is.na(now) || !identical(now, as.character(m$source_fingerprint))) {
      return(.cache_miss(key, "source changed"))
    }
  }
  recorded_transform <- m$transform_fingerprint
  has_transform <- !is.null(recorded_transform) && length(recorded_transform) &&
    !is.na(recorded_transform) && nzchar(recorded_transform)
  if (has_transform) {
    if (is.null(transform_context)) {
      return(.cache_miss(key, "transformation context was not supplied"))
    }
    current_transform <- tryCatch(.transform_fingerprint(transform_context),
                                  error = function(e) NA_character_)
    if (is.na(current_transform) ||
        !identical(current_transform, as.character(recorded_transform))) {
      return(.cache_miss(key, "transformation changed"))
    }
  } else if (!is.null(transform_context)) {
    return(.cache_miss(key, "entry has no transformation identity"))
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

#' Ingest a source using a verified cache
#'
#' Custom parsers must supply `transform_context` with `parser_id`,
#' `parser_version`, and `schema_version`. The context and `...` arguments are
#' fingerprinted so a changed sheet, contract, profile, or parser configuration
#' cannot reuse an obsolete object.
#'
#' @param source Source path(s).
#' @param parse Parser called as `parse(source, ...)`.
#' @param key,dir,format,fingerprint Cache settings.
#' @param transform_context Required for custom parsers; automatically generated
#'   for [read_tabular()].
#' @param ... Parser arguments included in the transformation fingerprint.
#' @return Cached or freshly parsed object.
#' @export
cached_ingest <- function(source, parse = read_tabular, key = NULL,
                          dir = getOption("tritonIngest.cache_dir"),
                          format = c("rds", "parquet"),
                          fingerprint = c("md5", "size_mtime"),
                          transform_context = NULL, ...) {
  format <- match.arg(format)
  fingerprint <- match.arg(fingerprint)
  dots <- list(...)
  if (is.null(transform_context)) {
    if (!identical(parse, read_tabular)) {
      stop("Custom `parse` functions require `transform_context` with parser_id, ",
           "parser_version, and schema_version.", call. = FALSE)
    }
    transform_context <- list(parser_id = "tritonIngest::read_tabular",
                              parser_version = .package_version(),
                              schema_version = "tabular/raw-text-v1")
  }
  context <- .validate_transform_context(transform_context)
  context$arguments <- .canonicalize(dots)
  hit <- read_cache(key = key, source = source, dir = dir, format = format,
                    transform_context = context)
  if (!is.null(hit)) return(hit)
  obj <- do.call(parse, c(list(source), dots))
  write_cache(obj, source = source, key = key, dir = dir, format = format,
              fingerprint = fingerprint, transform_context = context)
  obj
}
