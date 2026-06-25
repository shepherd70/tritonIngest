# profiles.R
# ---------------------------------------------------------------------------
# Persistence for named column-mapping profiles: record, per role, the column
# map (contract field -> source column) plus light provenance, so a known
# file->schema mapping can be re-applied without redoing it by hand.
#
# Profiles are JSON, one file per profile. The directory is supplied by the
# caller (or via options(tritonIngest.profiles_dir=)), so each consuming project
# controls where profiles live -- this package never hardcodes a data path.
# ---------------------------------------------------------------------------

#' Resolve (and optionally create) the mapping-profiles directory.
#'
#' @param dir Directory to store profiles in. Defaults to
#'   `getOption("tritonIngest.profiles_dir")`; errors if neither is set.
#' @param create Logical; create the directory if it does not exist.
#' @return Absolute path to the profiles directory.
#' @export
mapping_profiles_dir <- function(dir = getOption("tritonIngest.profiles_dir"),
                                 create = TRUE) {
  if (is.null(dir) || !nzchar(dir)) {
    stop("No profiles directory: pass `dir=` or set ",
         "options(tritonIngest.profiles_dir=).", call. = FALSE)
  }
  if (create && !dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  dir
}

# Sanitise a profile name into a safe file stem.
.mp_slug <- function(name) {
  s <- tolower(trimws(as.character(name)))
  s <- gsub("[^a-z0-9]+", "-", s)
  s <- gsub("^-+|-+$", "", s)
  if (!nzchar(s)) stop("Profile name must contain at least one alphanumeric character.", call. = FALSE)
  s
}

#' List saved mapping profiles.
#'
#' @param dir Profiles directory (see [mapping_profiles_dir()]).
#' @return A tibble with `name`, `file`, and `modified` (POSIXct), newest first;
#'   zero rows if none exist.
#' @export
list_mapping_profiles <- function(dir = getOption("tritonIngest.profiles_dir")) {
  d <- mapping_profiles_dir(dir, create = FALSE)
  empty <- tibble::tibble(name = character(0), file = character(0),
                          modified = as.POSIXct(character(0)))
  if (!dir.exists(d)) return(empty)
  files <- list.files(d, pattern = "\\.json$", full.names = TRUE)
  if (length(files) == 0) return(empty)
  names_vec <- vapply(files, function(f) {
    nm <- tryCatch(jsonlite::fromJSON(f)$name, error = function(e) NULL)
    nm %||% tools::file_path_sans_ext(basename(f))
  }, character(1))
  tibble::tibble(
    name     = unname(names_vec),
    file     = files,
    modified = file.mtime(files)
  ) |> dplyr::arrange(dplyr::desc(modified))
}

#' Save a mapping profile to disk.
#'
#' @param name Human-readable profile name (also used to derive the filename).
#' @param mappings A named list keyed by role; each element a named list/char
#'   vector of `contract field -> source column`.
#' @param meta Optional named list of provenance (e.g. source kind, sheet).
#' @param dir Profiles directory (see [mapping_profiles_dir()]).
#' @param overwrite Logical; allow overwriting an existing same-named profile.
#' @return The path to the written JSON file (invisibly).
#' @export
save_mapping_profile <- function(name, mappings, meta = NULL,
                                 dir = getOption("tritonIngest.profiles_dir"),
                                 overwrite = TRUE) {
  stopifnot(is.list(mappings))
  slug <- .mp_slug(name)
  path <- file.path(mapping_profiles_dir(dir, create = TRUE), paste0(slug, ".json"))
  if (file.exists(path)) {
    existing <- tryCatch(jsonlite::fromJSON(path)$name, error = function(e) NULL)
    # A different name mapping to the same slug is a collision, not an overwrite:
    # silently replacing it would destroy an unrelated saved profile.
    if (!is.null(existing) && !identical(as.character(existing), as.character(name))) {
      stop(sprintf(paste0("Profile name '%s' collides with existing profile ",
                          "'%s' (both map to '%s.json'); choose a more distinct name."),
                   name, existing, slug), call. = FALSE)
    }
    if (!overwrite) {
      stop(sprintf("Profile '%s' already exists (overwrite = FALSE).", name), call. = FALSE)
    }
  }
  # Coerce each role's mapping to a *named list* so jsonlite serialises it as a
  # JSON object (key-preserving), not a positional array.
  mappings <- lapply(mappings, as.list)
  payload <- list(
    name     = as.character(name),
    schema   = "triton-mapping-profile/v1",
    saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    mappings = mappings,
    meta     = meta %||% list()
  )
  jsonlite::write_json(payload, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(path)
}

#' Load a mapping profile from disk.
#'
#' Accepts either a profile name (resolved against `dir`) or a direct path to a
#' `.json` file.
#'
#' @param name_or_path Profile name or path to a profile JSON file.
#' @param dir Profiles directory (see [mapping_profiles_dir()]).
#' @return A list with `name`, `mappings`, `meta`, `saved_at`. Each role's
#'   mapping is a named character vector (contract field -> source column).
#' @export
load_mapping_profile <- function(name_or_path,
                                 dir = getOption("tritonIngest.profiles_dir")) {
  path <- if (file.exists(name_or_path)) {
    name_or_path
  } else {
    file.path(mapping_profiles_dir(dir, create = FALSE),
              paste0(.mp_slug(name_or_path), ".json"))
  }
  if (!file.exists(path)) {
    stop(sprintf("No mapping profile found at or named '%s'.", name_or_path), call. = FALSE)
  }
  raw <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  mappings <- lapply(raw$mappings %||% list(), function(m) {
    v <- unlist(m, use.names = TRUE)
    stats::setNames(as.character(v), names(v))
  })
  list(
    name     = raw$name %||% tools::file_path_sans_ext(basename(path)),
    mappings = mappings,
    meta     = raw$meta %||% list(),
    saved_at = raw$saved_at %||% NA_character_
  )
}

#' Delete a mapping profile.
#'
#' @param name_or_path Profile name or path to a profile JSON file.
#' @param dir Profiles directory (see [mapping_profiles_dir()]).
#' @return `TRUE` if a file was removed, `FALSE` if none existed.
#' @export
delete_mapping_profile <- function(name_or_path,
                                   dir = getOption("tritonIngest.profiles_dir")) {
  path <- if (file.exists(name_or_path)) {
    name_or_path
  } else {
    file.path(mapping_profiles_dir(dir, create = FALSE),
              paste0(.mp_slug(name_or_path), ".json"))
  }
  if (file.exists(path)) {
    file.remove(path)
    TRUE
  } else {
    FALSE
  }
}
