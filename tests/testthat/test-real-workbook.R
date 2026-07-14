.real_workbook_path <- function() {
  path <- Sys.getenv("TRITON_REAL_WORKBOOK", unset = "")
  testthat::skip_if(!nzchar(path),
                    "Set TRITON_REAL_WORKBOOK for secure real-workbook validation")
  testthat::skip_if_not(file.exists(path),
                        "TRITON_REAL_WORKBOOK does not identify a readable file")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.real_workbook_baseline <- function() {
  jsonlite::read_json(testthat::test_path(
    "fixtures", "real-workbook-baseline.json"), simplifyVector = TRUE)
}

.digest_cell_tokens <- function(tokens, rows, columns) {
  encoded <- vapply(tokens, function(value) {
    if (is.na(value)) return("N\n")
    value <- enc2utf8(value)
    paste0("V", nchar(value, type = "bytes"), ":", value, "\n")
  }, character(1), USE.NAMES = FALSE)
  payload <- paste0(rows, ":", columns, "\n", paste0(encoded, collapse = ""))
  digest::digest(payload, algo = "sha256", serialize = FALSE)
}

.raw_text_cell_digest <- function(x) {
  values <- as.matrix(x)
  tokens <- as.vector(t(values))
  tokens[!is.na(tokens) & tokens == ""] <- NA_character_
  .digest_cell_tokens(tokens, nrow(values), ncol(values))
}

.double_token <- function(value) {
  raw <- writeBin(as.double(value), raw(), size = 8L, endian = "big")
  paste0("D", paste0(sprintf("%02x", as.integer(raw)), collapse = ""))
}

.semantic_cell_digest <- function(x) {
  values <- as.matrix(x)
  tokens <- as.vector(t(values))
  number <- "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[Ee][+-]?[0-9]+)?$"
  tokens <- vapply(tokens, function(value) {
    if (is.na(value) || identical(value, "")) return(NA_character_)
    value <- gsub("\\r\\n?", "\n", enc2utf8(value), perl = TRUE)
    if (identical(value, "TRUE")) return("B1")
    if (identical(value, "FALSE")) return("B0")
    if (grepl(number, value, perl = TRUE)) return(.double_token(value))
    paste0("S", value)
  }, character(1), USE.NAMES = FALSE)
  .digest_cell_tokens(tokens, nrow(values), ncol(values))
}

.primary_sheet_observation <- function(path, expected) {
  raw <- read_tabular(path, sheet = expected$name, col_names = FALSE,
                      formula_policy = "error")
  matrix <- as.matrix(raw)
  list(
    name = expected$name,
    rows = nrow(raw),
    columns = ncol(raw),
    nonblank = sum(!is.na(matrix) & nzchar(matrix)),
    r_text_sha256 = .raw_text_cell_digest(raw),
    semantic_sha256 = .semantic_cell_digest(raw)
  )
}

test_that("approved real workbook matches its privacy-safe golden manifest", {
  path <- .real_workbook_path()
  baseline <- .real_workbook_baseline()

  expect_identical(
    digest::digest(file = path, algo = "sha256", serialize = FALSE),
    baseline$source$sha256
  )
  expect_equal(unname(file.info(path)$size), baseline$source$bytes)

  inventory <- inspect_workbook(path)
  expected_inventory <- baseline$inventory[, names(inventory)]
  expect_equal(inventory, tibble::as_tibble(expected_inventory))

  observed <- lapply(seq_len(nrow(baseline$primary_sheets)), function(i) {
    .primary_sheet_observation(path, baseline$primary_sheets[i, ])
  })
  observed <- dplyr::bind_rows(observed)
  expect_equal(observed, tibble::as_tibble(baseline$primary_sheets))
})

test_that("independent Python reader agrees cell-for-cell on primary sheets", {
  path <- .real_workbook_path()
  python <- Sys.getenv("TRITON_REAL_WORKBOOK_PYTHON", unset = "")
  testthat::skip_if(!nzchar(python),
                    "Set TRITON_REAL_WORKBOOK_PYTHON for cross-reader validation")
  testthat::skip_if_not(file.exists(python),
                        "TRITON_REAL_WORKBOOK_PYTHON is not executable")
  baseline <- .real_workbook_baseline()
  script <- testthat::test_path("fixtures", "independent-workbook-digest.py")
  args <- c(script, path, unlist(lapply(baseline$primary_sheets$name,
                                        function(name) c("--sheet", name))))
  output <- system2(python, shQuote(args), stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  if (!identical(status, 0L)) {
    testthat::fail(paste(output, collapse = "\n"))
  }
  independent <- jsonlite::fromJSON(paste(output, collapse = "\n"))

  expect_identical(independent$source_sha256, baseline$source$sha256)
  comparable <- c("name", "rows", "columns", "nonblank", "semantic_sha256")
  expect_equal(
    independent$sheets[, comparable],
    baseline$primary_sheets[, comparable]
  )
})

test_that("real-workbook transformations conserve measurements and censor tokens", {
  path <- .real_workbook_path()
  baseline <- .real_workbook_baseline()
  sheets <- read_all_sheets(path, col_names = FALSE, formula_policy = "allow")

  censor_pattern <- paste0("^\\s*(?:<|>|", intToUtf8(0x2264), "|",
                           intToUtf8(0x2265), ")")
  censored <- unlist(lapply(sheets, function(sheet) {
    values <- unlist(lapply(sheet, as.character), use.names = FALSE)
    values[!is.na(values) & grepl(censor_pattern, values, perl = TRUE)]
  }), use.names = FALSE)
  parsed <- parse_censored(censored)
  observed_censor <- list(
    tokens = length(censored),
    parsed = sum(parsed$censored %in% TRUE),
    left = sum(parsed$censor_direction == "left", na.rm = TRUE),
    right = sum(parsed$censor_direction == "right", na.rm = TRUE),
    unknown = sum(is.na(parsed$censored)),
    missing_limits = sum(parsed$censored %in% TRUE & is.na(parsed$censor_limit))
  )
  expect_equal(observed_censor, baseline$transformations$censor)

  expected <- baseline$transformations$wide
  raw <- sheets[[expected$sheet]]
  expect_warning(
    wide <- clean_table(raw, duplicate_names = "error"),
    "header cell.*position\\(s\\) 14"
  )
  layout <- detect_layout(wide)
  parameter_names_sha256 <- digest::digest(
    paste(unname(layout$value_like_cols), collapse = "\n"),
    algo = "sha256", serialize = FALSE
  )
  expect_identical(parameter_names_sha256, expected$parameter_names_sha256)

  parameter_values <- unlist(wide[layout$value_like_cols], use.names = FALSE)
  trimmed <- trimws(parameter_values)
  measured <- !is.na(trimmed) & nzchar(trimmed) &
    !toupper(trimmed) %in% toupper(c("-", "--", "n/a", "N/A"))
  melted <- melt_wide(wide, param_cols = layout$value_like_cols)
  expect_equal(nrow(melted), sum(measured))

  observed_wide <- list(
    sheet = expected$sheet,
    raw_rows = nrow(raw), raw_columns = ncol(raw),
    cleaned_rows = nrow(wide), cleaned_columns = ncol(wide),
    parameter_columns = length(layout$value_like_cols),
    parameter_names_sha256 = parameter_names_sha256,
    output_rows = nrow(melted), output_columns = ncol(melted),
    distinct_parameters = length(unique(melted$parameter))
  )
  expect_equal(observed_wide, expected)
})

test_that("real-workbook representative canonical bundle verifies and round-trips", {
  testthat::skip_if_not_installed("arrow")
  path <- .real_workbook_path()
  baseline <- .real_workbook_baseline()
  expected <- baseline$transformations$wide
  raw <- read_tabular(path, sheet = expected$sheet, col_names = FALSE,
                      formula_policy = "allow")
  expect_warning(
    wide <- clean_table(raw, duplicate_names = "error"),
    "header cell.*position\\(s\\) 14"
  )
  layout <- detect_layout(wide)
  melted <- melt_wide(wide, param_cols = layout$value_like_cols)
  contract <- as_contract(lapply(names(melted), function(name) {
    cf_field(name, type = "character", required = FALSE)
  }))
  manifest <- write_canonical_bundle(
    melted, tempfile("real-workbook-bundle-"), "wide-regression", path,
    contract, diagnostics = attr(wide, "diagnostics"),
    transform_context = list(
      parser_id = "triton-real-workbook-validation",
      parser_version = "1",
      schema_version = "real-workbook-regression/v1"
    )
  )
  bundle <- read_canonical_bundle(manifest, verify = TRUE, sources = path)
  expect_equal(bundle$data, tibble::as_tibble(melted))
  expect_equal(bundle$verification$sources$status, "verified")
  expect_identical(bundle$manifest$sources[[1]]$sha256,
                   baseline$source$sha256)
  expect_equal(bundle$manifest$artifacts[[1]]$row_count, nrow(melted))
  expect_equal(bundle$manifest$artifacts[[1]]$column_count, ncol(melted))
})
