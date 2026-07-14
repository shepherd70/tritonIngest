# artifacts.R
# Verified Parquet/Feather + manifest + diagnostics interchange bundles.

.package_version <- function() {
  tryCatch(as.character(utils::packageVersion("tritonIngest")),
           error = function(e) "0.7.0")
}

.validate_transform_context <- function(x, required = TRUE) {
  if (is.null(x)) {
    if (required) stop("`transform_context` is required.", call. = FALSE)
    return(NULL)
  }
  if (!is.list(x) || is.null(names(x))) {
    stop("`transform_context` must be a named list.", call. = FALSE)
  }
  need <- c("parser_id", "parser_version", "schema_version")
  missing <- need[!vapply(need, function(nm) {
    value <- x[[nm]]
    !is.null(value) && length(value) == 1L && !is.na(value) && nzchar(as.character(value))
  }, logical(1))]
  if (length(missing)) {
    stop("`transform_context` is missing required value(s): ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  .canonicalize(x)
}

.source_records <- function(sources) {
  sources <- as.character(sources)
  if (!length(sources)) stop("At least one source file is required.", call. = FALSE)
  lapply(sources, function(path) {
    if (!file.exists(path)) stop("Source file not found: ", path, call. = FALSE)
    list(name = basename(path), size_bytes = unname(file.info(path)$size),
         sha256 = .file_sha256(path), content_signature = sniff_format(path),
         sheet = NULL)
  })
}

.verify_bundle_sources <- function(expected, sources) {
  actual <- .source_records(sources)
  if (length(actual) != length(expected)) {
    stop("Canonical source count mismatch: manifest records ", length(expected),
         " source(s), but ", length(actual), " path(s) were supplied.",
         call. = FALSE)
  }
  fields <- c("name", "size_bytes", "content_signature", "sha256")
  labels <- c(name = "name", size_bytes = "size",
              content_signature = "content signature", sha256 = "checksum")
  for (i in seq_along(expected)) {
    for (field in fields) {
      wanted <- expected[[i]][[field]]
      found <- actual[[i]][[field]]
      if (is.null(wanted) ||
          !identical(as.character(found), as.character(wanted))) {
        stop("Canonical source ", labels[[field]], " mismatch at position ", i,
             " ('", actual[[i]]$name, "').", call. = FALSE)
      }
    }
  }
  list(status = "verified", count = length(actual))
}

#' Write a verified canonical interchange bundle
#'
#' @param x Data frame to write.
#' @param dir Output directory.
#' @param name Artifact stem.
#' @param sources Source file path(s).
#' @param contract Contract describing the canonical table.
#' @param diagnostics List of [tabular_diagnostic()] objects. `NULL` (default)
#'   uses diagnostics carried on `x` from ingestion and cleaning.
#' @param transform_context Named transformation identity; see [cached_ingest()].
#' @param format `"parquet"` (default) or `"feather"`.
#' @return Manifest path, invisibly.
#' @export
write_canonical_bundle <- function(x, dir, name, sources, contract, diagnostics = NULL,
                                   transform_context,
                                   format = c("parquet", "feather")) {
  format <- match.arg(format)
  if (!is.data.frame(x)) stop("`x` must be a data frame.", call. = FALSE)
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Canonical bundles require the 'arrow' package.", call. = FALSE)
  }
  context <- .validate_transform_context(transform_context)
  if (is.null(diagnostics)) diagnostics <- attr(x, "diagnostics") %||% list()
  diagnostics <- .as_diagnostics(diagnostics)
  dir <- normalizePath(dir, winslash = "/", mustWork = FALSE)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  stem <- .cache_slug(name)
  data_name <- paste0(stem, if (format == "parquet") ".parquet" else ".feather")
  diag_name <- paste0(stem, ".diagnostics.json")
  manifest_name <- paste0(stem, ".manifest.json")
  data_path <- file.path(dir, data_name)
  diag_path <- file.path(dir, diag_name)
  manifest_path <- file.path(dir, manifest_name)

  .atomic_write(data_path, function(tmp) {
    if (format == "parquet") arrow::write_parquet(as.data.frame(x), tmp)
    else arrow::write_feather(as.data.frame(x), tmp)
  })
  .atomic_write(diag_path, function(tmp) {
    jsonlite::write_json(diagnostics, tmp, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null")
  })

  source_info <- .source_records(sources)
  transform_fp <- .object_fingerprint(list(context = context,
                                            tritonIngest = .package_version()))
  contract_fp <- contract_fingerprint(contract)
  run_id <- substr(.object_fingerprint(list(sources = source_info,
                                             transformation = transform_fp,
                                             contract = contract_fp)), 1, 24)
  manifest <- list(
    schema = "tabular-artifact/v1",
    run_id = run_id,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    engine = list(name = "tritonIngest", language = "R",
                  version = .package_version(), spec_version = "1.0.0"),
    sources = source_info,
    artifacts = list(list(path = data_name, format = format,
                          sha256 = .file_sha256(data_path), row_count = nrow(x),
                          column_count = ncol(x),
                          schema_fingerprint = contract_fp)),
    transformation = list(id = as.character(context$parser_id),
                          version = as.character(context$parser_version),
                          configuration_fingerprint = transform_fp),
    diagnostics = list(path = diag_name, summary = .diagnostic_summary(diagnostics)),
    metadata = list()
  )
  .atomic_write(manifest_path, function(tmp) {
    jsonlite::write_json(manifest, tmp, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null")
  })
  invisible(manifest_path)
}

#' Read and verify a canonical interchange bundle
#'
#' @param manifest Path to a `tabular-artifact/v1` manifest.
#' @param verify Verify bundle-contained artifact checksums before reading. When
#'   `sources` is supplied, also verify current source identity.
#' @param sources Optional current source path(s), in manifest order. With
#'   `verify = TRUE`, basename, byte size, content signature, and SHA-256 must
#'   match the manifest. When omitted, source verification is explicitly
#'   reported as skipped in the returned `verification` record.
#' @return A list with `data`, `manifest`, `diagnostics`, and `verification`.
#' @export
read_canonical_bundle <- function(manifest, verify = TRUE, sources = NULL) {
  if (!file.exists(manifest)) stop("Manifest not found: ", manifest, call. = FALSE)
  m <- jsonlite::fromJSON(manifest, simplifyVector = FALSE)
  if (!identical(m$schema, "tabular-artifact/v1")) {
    stop("Unsupported canonical manifest schema: ", m$schema %||% "(missing)",
         call. = FALSE)
  }
  if (length(m$artifacts) != 1L) {
    stop("Canonical bundle must contain exactly one table artifact.", call. = FALSE)
  }
  root <- dirname(normalizePath(manifest, winslash = "/"))
  artifact <- m$artifacts[[1]]
  data_path <- file.path(root, artifact$path)
  diag_path <- file.path(root, m$diagnostics$path)
  if (!file.exists(data_path) || !file.exists(diag_path)) {
    stop("Canonical bundle is incomplete.", call. = FALSE)
  }
  if (isTRUE(verify)) {
    if (!identical(.file_sha256(data_path), artifact$sha256)) {
      stop("Canonical artifact checksum mismatch: ", artifact$path, call. = FALSE)
    }
    artifact_verification <- list(status = "verified", count = 1L)
    source_verification <- if (is.null(sources)) {
      list(status = "skipped", count = 0L,
           reason = "No current source paths were supplied")
    } else {
      .verify_bundle_sources(m$sources, sources)
    }
  } else {
    artifact_verification <- list(status = "skipped", count = 0L,
                                  reason = "verify = FALSE")
    source_verification <- list(status = "skipped", count = 0L,
                                reason = "verify = FALSE")
  }
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Reading canonical bundles requires the 'arrow' package.", call. = FALSE)
  }
  data <- switch(artifact$format,
    parquet = tibble::as_tibble(arrow::read_parquet(data_path)),
    feather = tibble::as_tibble(arrow::read_feather(data_path)),
    stop("Unsupported canonical artifact format: ", artifact$format, call. = FALSE)
  )
  diagnostics <- jsonlite::fromJSON(diag_path, simplifyVector = FALSE)
  list(data = data, manifest = m, diagnostics = diagnostics,
       verification = list(artifact = artifact_verification,
                           sources = source_verification))
}
