# profiles.R
# Versioned, contract/header-bound column-mapping profiles.

#' Resolve the mapping-profile directory
#'
#' @param dir Directory path.
#' @param create Create it when absent.
#' @return Normalized absolute path.
#' @export
mapping_profiles_dir <- function(dir = getOption("tritonIngest.profiles_dir"),
                                 create = TRUE) {
  if (is.null(dir) || length(dir) != 1L || is.na(dir) || !nzchar(dir)) {
    stop("No profiles directory: pass `dir=` or set options(tritonIngest.profiles_dir=).",
         call. = FALSE)
  }
  if (create && !dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir, winslash = "/", mustWork = FALSE)
}

.mp_slug <- function(name) {
  if (length(name) != 1L || is.na(name)) stop("Profile name must be one string.", call. = FALSE)
  s <- tolower(trimws(as.character(name)))
  s <- gsub("[^a-z0-9]+", "-", s)
  s <- gsub("^-+|-+$", "", s)
  if (!nzchar(s)) stop("Profile name must contain an alphanumeric character.", call. = FALSE)
  s
}

.profile_path <- function(name_or_path, dir) {
  if (file.exists(name_or_path)) return(normalizePath(name_or_path, winslash = "/"))
  file.path(mapping_profiles_dir(dir, create = FALSE), paste0(.mp_slug(name_or_path), ".json"))
}

.mapping_vectors <- function(mappings) {
  lapply(mappings %||% list(), function(m) {
    v <- unlist(m, use.names = TRUE)
    stats::setNames(as.character(v), names(v))
  })
}

.validate_profile_inputs <- function(mappings, contracts, source_cols) {
  if (!is.list(mappings) || is.null(names(mappings)) || any(!nzchar(names(mappings)))) {
    stop("`mappings` must be a named list of roles.", call. = FALSE)
  }
  if (!is.list(contracts) || is.null(names(contracts)) ||
      !setequal(names(contracts), names(mappings))) {
    stop("`contracts` must be a named list with the same roles as `mappings`.", call. = FALSE)
  }
  if (!is.list(source_cols) || is.null(names(source_cols)) ||
      !setequal(names(source_cols), names(mappings))) {
    stop("`source_cols` must be a named list with the same roles as `mappings`.", call. = FALSE)
  }
  mappings <- .mapping_vectors(mappings)
  contracts <- lapply(contracts[names(mappings)], as_contract)
  source_cols <- lapply(source_cols[names(mappings)], as.character)
  for (role in names(mappings)) {
    map <- mappings[[role]]
    if (is.null(names(map)) || any(!nzchar(names(map))) || anyDuplicated(names(map))) {
      stop("Mapping for role '", role, "' must have unique contract-field names.",
           call. = FALSE)
    }
    unknown_target <- setdiff(names(map), contracts[[role]]$field)
    unknown_source <- setdiff(unname(map[!is.na(map) & nzchar(map)]), source_cols[[role]])
    if (length(unknown_target)) {
      stop("Profile role '", role, "' maps unknown contract field(s): ",
           paste(unknown_target, collapse = ", "), call. = FALSE)
    }
    if (length(unknown_source)) {
      stop("Profile role '", role, "' maps source column(s) not in the current header: ",
           paste(unique(unknown_source), collapse = ", "), call. = FALSE)
    }
  }
  list(mappings = mappings, contracts = contracts, source_cols = source_cols)
}

.profile_payload <- function(name, mappings, contracts, source_cols, meta = NULL) {
  checked <- .validate_profile_inputs(mappings, contracts, source_cols)
  role_meta <- lapply(names(checked$mappings), function(role) list(
    contract_fingerprint = contract_fingerprint(checked$contracts[[role]]),
    header_fingerprint = .object_fingerprint(checked$source_cols[[role]]),
    source_columns = checked$source_cols[[role]]
  ))
  names(role_meta) <- names(checked$mappings)
  core <- list(
    name = as.character(name),
    schema = "triton-mapping-profile/v2",
    saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    mappings = lapply(checked$mappings, as.list),
    roles = role_meta,
    meta = meta %||% list()
  )
  core$fingerprint <- .object_fingerprint(core[c("schema", "mappings", "roles", "meta")])
  core
}

#' List mapping profiles
#'
#' @param dir Profiles directory.
#' @return Tibble with name, schema, file, and modified time.
#' @export
list_mapping_profiles <- function(dir = getOption("tritonIngest.profiles_dir")) {
  d <- mapping_profiles_dir(dir, create = FALSE)
  empty <- tibble::tibble(name = character(), schema = character(), file = character(),
                          modified = as.POSIXct(character()))
  if (!dir.exists(d)) return(empty)
  files <- list.files(d, pattern = "[.]json$", full.names = TRUE)
  if (!length(files)) return(empty)
  info <- lapply(files, function(f) tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE),
                                             error = function(e) list()))
  tibble::tibble(
    name = vapply(seq_along(files), function(i) info[[i]]$name %||%
                    tools::file_path_sans_ext(basename(files[i])), character(1)),
    schema = vapply(info, function(x) x$schema %||% "unknown", character(1)),
    file = files,
    modified = file.mtime(files)
  ) |> dplyr::arrange(dplyr::desc(modified))
}

#' Save a contract/header-bound mapping profile
#'
#' @param name Human-readable profile name.
#' @param mappings Named role -> field/source mapping list.
#' @param contracts Named role -> contract list.
#' @param source_cols Named role -> ordered source header list.
#' @param meta Additional provenance.
#' @param dir Profiles directory.
#' @param overwrite Permit replacing the same profile name.
#' @return Written path, invisibly.
#' @export
save_mapping_profile <- function(name, mappings, contracts, source_cols, meta = NULL,
                                 dir = getOption("tritonIngest.profiles_dir"),
                                 overwrite = TRUE) {
  slug <- .mp_slug(name)
  path <- file.path(mapping_profiles_dir(dir, create = TRUE), paste0(slug, ".json"))
  if (file.exists(path)) {
    existing <- tryCatch(jsonlite::fromJSON(path)$name, error = function(e) NULL)
    if (!is.null(existing) && !identical(as.character(existing), as.character(name))) {
      stop(sprintf("Profile '%s' collides with '%s' (both map to '%s.json').",
                   name, existing, slug), call. = FALSE)
    }
    if (!overwrite) stop(sprintf("Profile '%s' already exists.", name), call. = FALSE)
  }
  payload <- .profile_payload(name, mappings, contracts, source_cols, meta)
  .atomic_write(path, function(tmp) {
    jsonlite::write_json(payload, tmp, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null")
  })
  invisible(path)
}

#' Load and validate a mapping profile
#'
#' `triton-mapping-profile/v2` profiles require current contracts and ordered
#' source headers. Legacy v1 profiles are rejected unless `allow_legacy = TRUE`;
#' they remain unvalidated and should only be passed to [upgrade_mapping_profile()].
#'
#' @param name_or_path Profile name or JSON path.
#' @param contracts,source_cols Current named role lists.
#' @param dir Profiles directory.
#' @param allow_legacy Explicitly inspect a v1 profile.
#' @return Validated profile list.
#' @export
load_mapping_profile <- function(name_or_path, contracts = NULL, source_cols = NULL,
                                 dir = getOption("tritonIngest.profiles_dir"),
                                 allow_legacy = FALSE) {
  path <- .profile_path(name_or_path, dir)
  if (!file.exists(path)) {
    stop(sprintf("No mapping profile found at or named '%s'.", name_or_path), call. = FALSE)
  }
  raw <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
                  error = function(e) stop("Unreadable mapping profile: ",
                                           conditionMessage(e), call. = FALSE))
  schema <- raw$schema %||% "triton-mapping-profile/v1"
  mappings <- .mapping_vectors(raw$mappings)
  if (!identical(schema, "triton-mapping-profile/v2")) {
    if (!isTRUE(allow_legacy)) {
      stop("Legacy mapping profile rejected. Use allow_legacy = TRUE only to inspect ",
           "it, then upgrade_mapping_profile() with current contracts and headers.",
           call. = FALSE)
    }
    return(list(name = raw$name %||% tools::file_path_sans_ext(basename(path)),
                mappings = mappings, meta = raw$meta %||% list(),
                saved_at = raw$saved_at %||% NA_character_, schema = schema,
                fingerprint = NA_character_, legacy = TRUE, path = path))
  }
  if (is.null(contracts) || is.null(source_cols)) {
    stop("v2 profiles require current `contracts` and `source_cols` for compatibility validation.",
         call. = FALSE)
  }
  checked <- .validate_profile_inputs(mappings, contracts, source_cols)
  for (role in names(checked$mappings)) {
    stored <- raw$roles[[role]]
    if (is.null(stored)) stop("Profile is missing role metadata for '", role, "'.", call. = FALSE)
    current_contract <- contract_fingerprint(checked$contracts[[role]])
    current_header <- .object_fingerprint(checked$source_cols[[role]])
    if (!identical(stored$contract_fingerprint, current_contract) ||
        !identical(stored$header_fingerprint, current_header)) {
      stop("Mapping profile is stale for role '", role,
           "' (contract or ordered source header changed).", call. = FALSE)
    }
  }
  expected <- .object_fingerprint(raw[c("schema", "mappings", "roles", "meta")])
  if (!identical(raw$fingerprint, expected)) {
    stop("Mapping profile fingerprint mismatch; file may be corrupted or edited.", call. = FALSE)
  }
  list(name = raw$name, mappings = mappings, meta = raw$meta %||% list(),
       saved_at = raw$saved_at, schema = schema, fingerprint = raw$fingerprint,
       legacy = FALSE, path = path)
}

#' Upgrade a legacy mapping profile without overwriting it
#'
#' @param name_or_path Legacy profile name/path.
#' @param contracts,source_cols Current named role lists.
#' @param dir Profiles directory.
#' @param output_name Name for the new v2 profile.
#' @return New v2 profile path, invisibly.
#' @export
upgrade_mapping_profile <- function(name_or_path, contracts, source_cols,
                                    dir = getOption("tritonIngest.profiles_dir"),
                                    output_name = NULL) {
  old <- load_mapping_profile(name_or_path, dir = dir, allow_legacy = TRUE)
  if (!isTRUE(old$legacy)) stop("Profile is already v2; no upgrade needed.", call. = FALSE)
  output_name <- output_name %||% paste0(old$name, " v2")
  save_mapping_profile(output_name, old$mappings, contracts, source_cols,
                       meta = c(old$meta, list(upgraded_from = basename(old$path))),
                       dir = dir, overwrite = FALSE)
}

#' Delete a mapping profile
#'
#' @param name_or_path Profile name/path.
#' @param dir Profiles directory.
#' @return `TRUE` if removed.
#' @export
delete_mapping_profile <- function(name_or_path,
                                   dir = getOption("tritonIngest.profiles_dir")) {
  path <- .profile_path(name_or_path, dir)
  if (!file.exists(path)) return(FALSE)
  isTRUE(file.remove(path))
}
