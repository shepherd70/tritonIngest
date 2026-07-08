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
#' @param type One of `"character"`, `"numeric"`, `"integer"`, `"date"`.
#' @param required Logical; is the field required for the data to be usable?
#' @param synonyms Character vector of alternative source-column names that
#'   should map to this field (matched after name normalisation).
#' @param description Short human-readable description.
#' @return A field-spec list.
#' @export
cf_field <- function(name, type = c("character", "numeric", "integer", "date"),
                     required = FALSE, synonyms = character(0), description = "") {
  type <- match.arg(type)
  list(name = name, type = type, required = required,
       synonyms = synonyms, description = description)
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
    return(x)
  }
  if (!is.list(x) || tibble::is_tibble(x)) {
    stop("as_contract() expects a list of cf_field() specs or a contract tibble.")
  }
  tibble::tibble(
    field       = vapply(x, `[[`, character(1), "name"),
    type        = vapply(x, `[[`, character(1), "type"),
    required    = vapply(x, `[[`, logical(1),   "required"),
    synonyms    = lapply(x, function(f) f$synonyms %||% character(0)),
    description = vapply(x, function(f) f$description %||% "", character(1))
  )
}

#' Field names of a contract.
#'
#' @param contract A contract (list of specs or tibble).
#' @return Character vector of field names, in contract order.
#' @export
contract_fields <- function(contract) as_contract(contract)$field

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
.cf_coerce <- function(x, type) {
  switch(type,
    integer   = suppressWarnings(as.integer(round(as.numeric(x)))),
    numeric   = suppressWarnings(as.numeric(x)),
    character = as.character(x),
    date      = coerce_excel_date(x),
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
#'   `NA`.
#' @return A tibble with contract-named (subset of) columns.
#' @export
apply_column_map <- function(df, mapping, contract, coerce = TRUE,
                             warn_coercion = TRUE) {
  ct <- as_contract(contract)
  stopifnot(is.data.frame(df))

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
      if (is.null(ty)) next
      before <- out[[f]]
      after  <- .cf_coerce(before, ty)
      if (ty %in% c("numeric", "integer", "date")) {
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
    if (isTRUE(warn_coercion) && length(losses)) {
      warning("apply_column_map(): type coercion discarded non-missing values:\n  ",
              paste(losses, collapse = "\n  "),
              "\nparse_censored() recovers non-detects and over-range results that ",
              "as.numeric() destroys; parse before mapping a numeric field.",
              call. = FALSE)
    }
  }
  out
}

#' Validate a (mapped) data frame against a contract.
#'
#' Reports, per contract field, whether it is present and usable. Statuses:
#' `"ok"`, `"missing"` (column absent), `"all_na"` (present but every value NA),
#' and `"type_warn"` (declared numeric/integer but >50% non-coercible).
#'
#' @param df A data frame with contract-named columns.
#' @param contract A contract (list of specs or tibble).
#' @return A tibble: `field`, `required`, `status`, `severity`
#'   (`"error"`/`"warning"`/`"ok"`), `issue` (NA when ok).
#' @export
validate_against_contract <- function(df, contract) {
  ct <- as_contract(contract)

  rows <- purrr::pmap(
    list(ct$field, ct$type, ct$required),
    function(field, type, required) {
      present <- field %in% names(df)
      status  <- "ok"; issue <- NA_character_

      if (!present) {
        status <- "missing"
        issue  <- if (required) "Required field not mapped" else "Optional field not mapped"
      } else {
        x <- df[[field]]
        if (length(x) > 0 && all(is.na(x))) {
          status <- "all_na"
          issue  <- "Mapped column is entirely missing/NA"
        } else if (type %in% c("numeric", "integer")) {
          num <- suppressWarnings(as.numeric(x))
          n_bad <- sum(is.na(num) & !is.na(x))
          if (length(x) > 0 && n_bad / length(x) > 0.5) {
            status <- "type_warn"
            issue  <- sprintf("%d of %d values not coercible to %s",
                              n_bad, length(x), type)
          }
        }
      }

      severity <- dplyr::case_when(
        status == "ok"                  ~ "ok",
        status == "missing" & !required ~ "ok",
        status == "missing" &  required ~ "error",
        status == "all_na"  &  required ~ "error",
        TRUE                            ~ "warning"
      )

      tibble::tibble(field = field, required = required, status = status,
                     severity = severity, issue = issue)
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
    character = NA_character_, date = as.Date(NA), NA)
  for (i in seq_len(nrow(ct))) {
    f <- ct$field[i]
    if (!f %in% names(df)) df[[f]] <- na_for(ct$type[i])
  }
  df[, c(ct$field, setdiff(names(df), ct$field)), drop = FALSE]
}

#' Is a mapped frame ready to use for a contract?
#'
#' `TRUE` when no field has `severity == "error"`.
#'
#' @param df A data frame with contract-named columns.
#' @param contract A contract (list of specs or tibble).
#' @return Logical scalar.
#' @export
contract_is_ready <- function(df, contract) {
  v <- validate_against_contract(df, contract)
  !any(v$severity == "error")
}
