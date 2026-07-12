# contract.R
# ---------------------------------------------------------------------------
# Declarative column contracts: map an arbitrary source table's columns onto a
# caller-declared schema, then validate conformance.
#
# A contract is just a list of field specs (built with cf_field()), turned into
# a tibble by as_contract(). Unlike a role-keyed global, the contract is passed
# in explicitly, so each consuming package owns its own schemas and this package
# stays domain-agnostic.
# ---------------------------------------------------------------------------

#' Build one contract field specification.
#'
#' @param name Contract field name (the canonical output column name).
#' @param type One of `"character"`, `"numeric"`, `"integer"`, `"logical"`,
#'   `"date"`, `"datetime"`, or `"time"`.
#' @param required Logical; is the field required for the data to be usable?
#' @param synonyms Character vector of alternative source-column names that
#'   should map to this field (matched after name normalisation).
#' @param description Short human-readable description.
#' @param formats Optional strict date/datetime/time parse formats.
#' @param tz Time zone for datetime parsing.
#' @return A field-spec list.
#' @export
cf_field <- function(name,
                     type = c("character", "numeric", "integer", "logical",
                              "date", "datetime", "time"),
                     required = FALSE, synonyms = character(0), description = "",
                     formats = NULL, tz = "UTC") {
  type <- match.arg(type)
  list(name = name, type = type, required = required,
       synonyms = synonyms, description = description, formats = formats, tz = tz)
}

#' Coerce field specs into a contract tibble.
#'
#' Accepts a list of [cf_field()] specs, or an already-built contract tibble
#' (idempotent), so engine functions can take either form.
#'
#' @param x A list of [cf_field()] specs, or a contract tibble.
#' @return A tibble with columns `field`, `type`, `required`, `synonyms`
#'   (list-column), `description`.
#' @export
as_contract <- function(x) {
  if (tibble::is_tibble(x) &&
      all(c("field", "type", "required", "synonyms") %in% names(x))) {
    out <- x
    if (!"description" %in% names(out)) out$description <- rep("", nrow(out))
    if (!"formats" %in% names(out)) out$formats <- rep(list(NULL), nrow(out))
    if (!"tz" %in% names(out)) out$tz <- rep("UTC", nrow(out))
  } else {
    if (!is.list(x) || tibble::is_tibble(x)) {
      stop("as_contract() expects a list of cf_field() specs or a contract tibble.",
           call. = FALSE)
    }
    required_keys <- c("name", "type", "required")
    bad <- !vapply(x, function(f) is.list(f) && all(required_keys %in% names(f)), logical(1))
    if (any(bad)) {
      stop("Every contract field must be created with cf_field(); malformed position(s): ",
           paste(which(bad), collapse = ", "), call. = FALSE)
    }
    out <- tibble::tibble(
      field       = vapply(x, `[[`, character(1), "name"),
      type        = vapply(x, `[[`, character(1), "type"),
      required    = vapply(x, `[[`, logical(1), "required"),
      synonyms    = lapply(x, function(f) f$synonyms %||% character(0)),
      description = vapply(x, function(f) f$description %||% "", character(1)),
      formats     = lapply(x, function(f) f$formats %||% NULL),
      tz          = vapply(x, function(f) f$tz %||% "UTC", character(1))
    )
  }

  allowed <- c("character", "numeric", "integer", "logical", "date", "datetime", "time")
  if (anyNA(out$field) || any(!nzchar(trimws(out$field)))) {
    stop("Contract field names must be non-empty.", call. = FALSE)
  }
  if (anyDuplicated(out$field)) {
    stop("Contract field names must be unique; duplicated: ",
         paste(unique(out$field[duplicated(out$field)]), collapse = ", "), call. = FALSE)
  }
  invalid_types <- setdiff(unique(out$type), allowed)
  if (length(invalid_types)) {
    stop("Unsupported contract type(s): ", paste(invalid_types, collapse = ", "),
         call. = FALSE)
  }
  if (!is.logical(out$required) || anyNA(out$required)) {
    stop("Contract `required` values must be non-missing logicals.", call. = FALSE)
  }
  if (any(!vapply(out$synonyms, is.character, logical(1)))) {
    stop("Contract synonyms must be character vectors.", call. = FALSE)
  }
  if (any(!vapply(out$formats, function(v) is.null(v) ||
                  (is.character(v) && length(v) && !anyNA(v) && all(nzchar(v))),
                  logical(1)))) {
    stop("Contract formats must be NULL or non-empty character vectors.", call. = FALSE)
  }
  if (anyNA(out$tz) || any(!nzchar(out$tz))) {
    stop("Contract time zones must be non-empty strings.", call. = FALSE)
  }
  out <- tibble::as_tibble(out[, c("field", "type", "required", "synonyms",
                                   "description", "formats", "tz")])
  class(out) <- unique(c("triton_contract", class(out)))
  out
}

#' Field names of a contract.
#'
#' @param contract A contract (list of specs or tibble).
#' @return Character vector of field names, in contract order.
#' @export
contract_fields <- function(contract) as_contract(contract)$field

#' Deterministic fingerprint of a contract
#'
#' @param contract Contract object.
#' @return SHA-256 hexadecimal fingerprint.
#' @export
contract_fingerprint <- function(contract) {
  ct <- as_contract(contract)
  .object_fingerprint(unclass(as.data.frame(ct)))
}

# Normalise a column name for matching (lightweight clean_names mimic).
.cf_norm <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)   # non-alnum runs -> single underscore
  x <- gsub("^_+|_+$", "", x)        # trim leading/trailing underscores
  x <- gsub("_+", "_", x)            # collapse repeats
  x
}

#' Auto-map source columns onto a contract.
#'
#' For each contract field, picks the best source column by: (1) normalised exact
#' match on the field name, (2) normalised match against the field's synonyms,
#' (3) optionally, a fuzzy match (`utils::adist`) within an edit-distance budget.
#' A source column is used at most once; earlier (higher-priority) fields win ties,
#' so the mapping depends on contract field **order**.
#'
#' @section Fuzzy matching is opt-in:
#' `max_distance` defaults to `0` (exact and synonym matching only). Edit distance
#' over short, systematically-related analyte names is unsafe: `"LEPH_C10_C19"` is
#' distance 1 from `"EPH_C10_C19"` but distance 9 from the correct
#' `"LEPH_C10_C19_less_PAH"`, and a two-character synonym such as `"dl"` is
#' distance 2 from a `"pH"` column. Set `max_distance = 2L` to restore the
#' pre-0.6.0 behaviour; every fuzzy match is then reported with a warning.
#'
#' @section Exact names outrank synonyms:
#' A contract field always binds to a column whose *name* matches it, even when a
#' synonym matches a different column. That is intended -- but it is also how a
#' column innocently named `Analyte` that holds a sample-matrix label (`"Effluent"`)
#' captures the `analyte` field ahead of the `parameter` column holding the real
#' analyte names. When both are present, `auto_map()` warns.
#'
#' @param source_cols Character vector of column names from the source data.
#' @param contract A contract (list of specs or tibble).
#' @param max_distance Integer max edit distance for the fuzzy fallback. `0`
#'   (default) disables fuzzy matching.
#' @param warn Emit warnings for fuzzy matches and exact/synonym ambiguity.
#' @return A named list, one element per contract field, holding the matched
#'   source-column name or `NA_character_`.
#' @export
auto_map <- function(source_cols, contract, max_distance = 0L, warn = TRUE) {
  ct       <- as_contract(contract)
  src      <- as.character(source_cols)
  src_norm <- .cf_norm(src)
  used     <- rep(FALSE, length(src))

  pick <- function(candidate_idx) {
    candidate_idx <- candidate_idx[!used[candidate_idx]]
    if (length(candidate_idx) == 0) return(NA_integer_)
    candidate_idx[1]
  }

  out       <- stats::setNames(vector("list", nrow(ct)), ct$field)
  fuzzy     <- character(0)
  exact_syn <- list()   # field -> synonym-matched source indices, decided post-pass

  for (i in seq_len(nrow(ct))) {
    field_norm <- .cf_norm(ct$field[i])
    syn_norm   <- .cf_norm(ct$synonyms[[i]])

    hit <- pick(which(src_norm == field_norm))
    if (!is.na(hit) && length(syn_norm)) {
      # Exact-name match won. Remember any *other* column a synonym also matches,
      # but decide whether that is a real ambiguity only after the whole mapping
      # is known: a column that some other field legitimately claims is not
      # contested. Deciding here would false-positive on that case.
      exact_syn[[ct$field[i]]] <- list(
        col = src[hit],
        others = setdiff(which(src_norm %in% syn_norm), hit))
    }
    if (is.na(hit) && length(syn_norm)) {
      hit <- pick(which(src_norm %in% syn_norm))
    }
    if (is.na(hit) && max_distance > 0) {
      targets <- unique(c(field_norm, syn_norm))
      free    <- which(!used)
      if (length(free)) {
        d  <- vapply(free, function(j) min(utils::adist(src_norm[j], targets)), numeric(1))
        ok <- which(d <= max_distance)
        if (length(ok)) {
          hit <- free[ok[which.min(d[ok])]]
          fuzzy <- c(fuzzy, sprintf("'%s' -> '%s' (edit distance %d)",
                                    ct$field[i], src[hit], as.integer(min(d[ok]))))
        }
      }
    }

    if (!is.na(hit)) {
      used[hit] <- TRUE
      out[[ct$field[i]]] <- src[hit]
    } else {
      out[[ct$field[i]]] <- NA_character_
    }
  }

  # Ambiguity is only real when the synonym-matched other column is claimed by NO
  # field. A column that ended up mapped (to this or any field) is not contested.
  ambig <- character(0)
  for (f in names(exact_syn)) {
    contested <- exact_syn[[f]]$others[!used[exact_syn[[f]]$others]]
    if (length(contested)) {
      ambig <- c(ambig, sprintf(
        "'%s' bound to column '%s' by exact name, but synonym(s) also match unmapped column(s) %s",
        f, exact_syn[[f]]$col, paste0("'", src[contested], "'", collapse = ", ")))
    }
  }

  if (isTRUE(warn) && length(fuzzy)) {
    warning("auto_map(): matched by fuzzy edit distance, not by name or synonym:\n  ",
            paste(fuzzy, collapse = "\n  "),
            "\nVerify each; set max_distance = 0 to disable fuzzy matching.", call. = FALSE)
  }
  if (isTRUE(warn) && length(ambig)) {
    warning("auto_map(): ambiguous mapping (exact name wins over synonym):\n  ",
            paste(ambig, collapse = "\n  "),
            "\nCheck that the exactly-named column really holds this field's data.",
            call. = FALSE)
  }
  out
}

# Coerce a single vector to a contract type. The integer path rounds half-to-
# even (round(80.5) == 80) and returns NA above .Machine$integer.max with the
# overflow warning suppressed -- fine for years/counts, but declare a large
# numeric id as "numeric" or "character", not "integer".
.cf_datetime <- function(x, formats = NULL, tz = "UTC") {
  if (inherits(x, "POSIXct")) return(as.POSIXct(x, tz = tz))
  if (inherits(x, "Date")) return(as.POSIXct(x, tz = tz))
  formats <- formats %||% c("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S",
                            "%Y-%m-%d %H:%M")
  s <- trimws(as.character(x))
  out <- as.POSIXct(rep(NA_real_, length(s)), origin = "1970-01-01", tz = tz)
  numeric <- suppressWarnings(as.numeric(s))
  serial <- !is.na(numeric) & numeric >= 1 & numeric <= 2958465
  out[serial] <- as.POSIXct("1899-12-30", tz = tz) + numeric[serial] * 86400
  for (fmt in formats) {
    todo <- which(!serial & is.na(out) & !is.na(s) & nzchar(s))
    if (!length(todo)) break
    cand <- todo[grepl(.fmt_regex(fmt), s[todo])]
    if (!length(cand)) next
    parsed <- as.POSIXct(strptime(s[cand], format = fmt, tz = tz))
    ok <- !is.na(parsed)
    out[cand[ok]] <- parsed[ok]
  }
  out
}

.cf_time <- function(x, formats = NULL) {
  if (inherits(x, "hms")) return(x)
  formats <- formats %||% c("%H:%M:%S", "%H:%M")
  s <- trimws(as.character(x))
  seconds <- rep(NA_real_, length(s))
  numeric <- suppressWarnings(as.numeric(s))
  fraction <- !is.na(numeric) & numeric >= 0 & numeric < 1
  seconds[fraction] <- numeric[fraction] * 86400
  for (fmt in formats) {
    todo <- which(!fraction & is.na(seconds) & !is.na(s) & nzchar(s))
    if (!length(todo)) break
    cand <- todo[grepl(.fmt_regex(fmt), s[todo])]
    if (!length(cand)) next
    parsed <- strptime(s[cand], format = fmt, tz = "UTC")
    ok <- !is.na(parsed)
    seconds[cand[ok]] <- parsed$hour[ok] * 3600 + parsed$min[ok] * 60 + parsed$sec[ok]
  }
  hms::as_hms(seconds)
}

.cf_coerce <- function(x, type, formats = NULL, tz = "UTC") {
  switch(type,
    integer   = {
      value <- suppressWarnings(as.numeric(x))
      valid <- !is.na(value) & value == trunc(value) &
        value >= -.Machine$integer.max - 1 & value <= .Machine$integer.max
      out <- rep(NA_integer_, length(value)); out[valid] <- as.integer(value[valid]); out
    },
    numeric   = suppressWarnings(as.numeric(x)),
    character = as.character(x),
    logical   = {
      token <- tolower(trimws(as.character(x)))
      out <- rep(NA, length(token))
      out[token %in% c("true", "t", "1")] <- TRUE
      out[token %in% c("false", "f", "0")] <- FALSE
      out
    },
    date      = if (inherits(x, "Date")) x else
      coerce_excel_date(x, formats = formats %||% c("%Y-%m-%d", "%Y/%m/%d")),
    datetime  = .cf_datetime(x, formats = formats, tz = tz),
    time      = .cf_time(x, formats = formats),
    x
  )
}

#' Apply a column mapping to a source data frame.
#'
#' Selects the mapped source columns, renames them to their contract field
#' names, and (optionally) coerces each to its declared type. Fields whose
#' mapping is `NA`/missing are dropped -- use [validate_against_contract()]
#' afterwards to flag missing required fields. Unreferenced source columns are
#' discarded, so downstream code sees only contract-named columns.
#'
#' @section Coercion is lossy, and says so:
#' Coercing a `numeric` field runs `as.numeric()`, which turns every censored
#' result (`"<0.25"`, `"ND"`, `">2420"`) into `NA`. That is exactly the
#' information [parse_censored()] exists to preserve, and the contract path does
#' not call it. Parse first, then map the parsed columns. When coercion does drop
#' non-missing values, `warn_coercion` reports the field, the count and a few
#' example tokens rather than letting them vanish.
#'
#' @param df A source data frame.
#' @param mapping Named list/character vector: contract field -> source column.
#' @param contract A contract (list of specs or tibble).
#' @param coerce Logical; coerce each output column to its declared type.
#' @param warn_coercion Warn when coercion turns non-missing source values into
#'   `NA`. Deprecated; use `loss`.
#' @param loss Policy when coercion would discard populated values: error by
#'   default, or explicitly warn/allow.
#' @return A tibble with contract-named (subset of) columns.
#' @export
apply_column_map <- function(df, mapping, contract, coerce = TRUE,
                             warn_coercion = NULL,
                             loss = c("error", "warn", "allow")) {
  loss_missing <- missing(loss)
  loss <- match.arg(loss)
  if (!is.null(warn_coercion) && loss_missing) {
    warning("`warn_coercion` is deprecated; use `loss=`.", call. = FALSE)
    loss <- if (isTRUE(warn_coercion)) "warn" else "allow"
  }
  ct <- as_contract(contract)
  stopifnot(is.data.frame(df))

  if (is.null(names(mapping)) || any(!nzchar(names(mapping)))) {
    stop("`mapping` must be named contract-field -> source-column.", call. = FALSE)
  }
  unknown_targets <- setdiff(names(mapping), ct$field)
  if (length(unknown_targets)) {
    stop("Mapping names field(s) absent from the contract: ",
         paste(unknown_targets, collapse = ", "), call. = FALSE)
  }
  if (anyDuplicated(names(mapping))) stop("Mapping target fields must be unique.", call. = FALSE)

  mapping <- mapping[!vapply(mapping, function(v) is.null(v) || is.na(v) || !nzchar(v), logical(1))]
  mapping <- mapping[vapply(mapping, function(v) v %in% names(df), logical(1))]
  if (length(mapping) == 0) {
    return(tibble::as_tibble(df[, character(0), drop = FALSE]))
  }

  out <- tibble::as_tibble(df[, unlist(mapping), drop = FALSE])
  names(out) <- names(mapping)

  if (coerce) {
    types  <- stats::setNames(ct$type, ct$field)
    losses <- character(0)
    for (f in names(out)) {
      ty <- types[[f]]
      row <- match(f, ct$field)
      before <- out[[f]]
      after  <- .cf_coerce(before, ty, ct$formats[[row]], ct$tz[row])
      if (ty %in% c("numeric", "integer", "logical", "date", "datetime", "time")) {
        present <- !is.na(before) & nzchar(trimws(as.character(before)))
        lost    <- which(is.na(after) & present)
        if (length(lost)) {
          ex <- utils::head(unique(as.character(before)[lost]), 3)
          losses <- c(losses, sprintf("'%s' (%s): %d of %d non-missing values -> NA (e.g. %s)",
                                      f, ty, length(lost), sum(present),
                                      paste0("'", ex, "'", collapse = ", ")))
        }
      }
      out[[f]] <- after
    }
    if (length(losses)) {
      msg <- paste0("apply_column_map(): type coercion discarded non-missing values:\n  ",
                    paste(losses, collapse = "\n  "),
                    "\nPreserve raw measurement text and parse it before numeric coercion.")
      if (loss == "error") stop(msg, call. = FALSE)
      if (loss == "warn") warning(msg, call. = FALSE)
    }
  }
  out
}

#' Validate a (mapped) data frame against a contract.
#'
#' Reports, per contract field, whether it is present, populated, and valid for
#' its declared type.
#'
#' @param df A data frame with contract-named columns.
#' @param contract A contract (list of specs or tibble).
#' @param policy `"strict"` validates values and structure; `"structure"`
#'   checks only presence and population.
#' @param max_invalid_fraction Maximum tolerated fraction of invalid populated
#'   values before a field becomes an error.
#' @return A tibble: `field`, `required`, `status`, `severity`
#'   (`"error"`/`"warning"`/`"ok"`), `issue`, and total/populated/missing/
#'   invalid counts plus the invalid fraction.
#' @export
validate_against_contract <- function(df, contract,
                                      policy = c("strict", "structure"),
                                      max_invalid_fraction = 0) {
  policy <- match.arg(policy)
  if (length(max_invalid_fraction) != 1L || is.na(max_invalid_fraction) ||
      max_invalid_fraction < 0 || max_invalid_fraction > 1) {
    stop("`max_invalid_fraction` must be between 0 and 1.", call. = FALSE)
  }
  ct <- as_contract(contract)

  rows <- purrr::pmap(
    list(ct$field, ct$type, ct$required, ct$formats, ct$tz),
    function(field, type, required, formats, tz) {
      present <- field %in% names(df)
      status  <- "ok"; issue <- NA_character_
      n_total <- nrow(df); n_present <- 0L; n_missing <- n_total; n_invalid <- 0L
      invalid_fraction <- 0

      if (!present) {
        status <- "missing"
        issue  <- if (required) "Required field not mapped" else "Optional field not mapped"
      } else {
        x <- df[[field]]
        populated <- !is.na(x) & nzchar(trimws(as.character(x)))
        n_present <- sum(populated)
        n_missing <- length(x) - n_present
        if (length(x) == 0) {
          status <- "empty"
          issue <- "Mapped table has zero rows"
        } else if (n_present == 0) {
          status <- "all_na"
          issue  <- "Mapped column is entirely missing/NA"
        } else if (policy == "strict" && type != "character") {
          parsed <- suppressWarnings(.cf_coerce(x, type, formats, tz))
          n_invalid <- sum(populated & is.na(parsed))
          invalid_fraction <- n_invalid / n_present
          if (n_invalid > 0 && invalid_fraction > max_invalid_fraction) {
            status <- "invalid"
            issue <- sprintf("%d of %d populated values not coercible to %s",
                             n_invalid, n_present, type)
          } else if (n_invalid > 0) {
            status <- "partial_invalid"
            issue <- sprintf("%d of %d populated values not coercible to %s",
                             n_invalid, n_present, type)
          }
        }
      }

      severity <- dplyr::case_when(
        status == "ok"                  ~ "ok",
        status == "missing" & !required ~ "ok",
        status %in% c("missing", "all_na", "empty", "invalid") & required ~ "error",
        TRUE                            ~ "warning"
      )

      tibble::tibble(field = field, required = required, status = status,
                     severity = severity, issue = issue,
                     total = as.integer(n_total), populated = as.integer(n_present),
                     missing = as.integer(n_missing), invalid = as.integer(n_invalid),
                     invalid_fraction = as.numeric(invalid_fraction))
    }
  )
  dplyr::bind_rows(rows)
}

#' Complete a mapped frame to the full contract schema.
#'
#' Adds any contract field not already present as a typed all-`NA` column, in
#' contract order, so downstream code that references optional columns
#' unconditionally still finds them. Run [validate_against_contract()] on the
#' pre-completion frame so genuinely-missing required fields are still reported.
#'
#' @param df A data frame with contract-named columns.
#' @param contract A contract (list of specs or tibble).
#' @return A tibble containing every contract field plus any extra columns
#'   already on `df`, with contract fields ordered first.
#' @export
complete_to_contract <- function(df, contract) {
  ct  <- as_contract(contract)
  df  <- tibble::as_tibble(df)
  na_for <- function(type) switch(type,
    integer   = NA_integer_, numeric = NA_real_,
    logical = NA, character = NA_character_, date = as.Date(NA),
    datetime = as.POSIXct(NA, origin = "1970-01-01", tz = "UTC"),
    time = hms::as_hms(NA_real_), NA)
  for (i in seq_len(nrow(ct))) {
    f <- ct$field[i]
    if (!f %in% names(df)) df[[f]] <- na_for(ct$type[i])
  }
  df[, c(ct$field, setdiff(names(df), ct$field)), drop = FALSE]
}

#' Is a mapped frame ready to use for a contract?
#'
#' Strict readiness requires the minimum row count and no unresolved field
#' warnings or errors. Structural-only readiness is available explicitly.
#'
#' @param df A data frame with contract-named columns.
#' @param contract A contract (list of specs or tibble).
#' @param policy `"strict"` or explicit structural-only `"structure"` policy.
#' @param min_rows Minimum number of rows required.
#' @param max_invalid_fraction Maximum tolerated invalid populated fraction.
#' @param allow_warnings Treat warning-only validation results as ready.
#' @return Logical scalar.
#' @export
contract_is_ready <- function(df, contract,
                              policy = c("strict", "structure"), min_rows = 1L,
                              max_invalid_fraction = 0,
                              allow_warnings = FALSE) {
  policy <- match.arg(policy)
  if (length(min_rows) != 1L || is.na(min_rows) || min_rows < 0) {
    stop("`min_rows` must be one non-negative integer.", call. = FALSE)
  }
  if (nrow(df) < min_rows) return(FALSE)
  v <- validate_against_contract(df, contract, policy = policy,
                                 max_invalid_fraction = max_invalid_fraction)
  if (isTRUE(allow_warnings)) !any(v$severity == "error")
  else all(v$severity == "ok")
}
