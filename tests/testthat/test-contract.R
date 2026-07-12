# A small fish-catch-like contract exercises the engine end to end.
test_contract <- function() {
  as_contract(list(
    cf_field("year",      "integer",   required = TRUE,  synonyms = c("yr", "sample_year")),
    cf_field("site",      "character", required = TRUE,  synonyms = c("station", "site_id")),
    cf_field("species",   "character", required = TRUE),
    cf_field("length_mm", "numeric",   required = TRUE,  synonyms = c("fork_length", "fl_mm")),
    cf_field("weight_g",  "numeric",   required = FALSE)
  ))
}

test_that("as_contract builds a tibble and is idempotent", {
  ct <- test_contract()
  expect_s3_class(ct, "tbl_df")
  expect_equal(contract_fields(ct), c("year", "site", "species", "length_mm", "weight_g"))
  expect_identical(as_contract(ct), ct)         # idempotent on a contract tibble
})

test_that("auto_map matches by exact name and synonym; fuzzy is opt-in (RC6)", {
  cols <- c("Year", "Station", "Speces", "Fork Length")  # 'Speces' = typo of species

  # fuzzy is OFF by default from 0.6.0: the typo no longer silently binds
  m0 <- auto_map(cols, test_contract())
  expect_equal(m0$year, "Year")                 # exact (normalised)
  expect_equal(m0$site, "Station")              # synonym
  expect_true(is.na(m0$species))                # was "Speces" via edit distance 1
  expect_equal(m0$length_mm, "Fork Length")     # synonym (fork_length)

  # opt in, and every fuzzy match is announced
  expect_warning(m <- auto_map(cols, test_contract(), max_distance = 2L),
                 "matched by fuzzy edit distance")
  expect_equal(m$species, "Speces")
  expect_true(is.na(m$weight_g))                # nothing left within the fuzzy budget
  expect_silent(auto_map(cols, test_contract(), max_distance = 2L, warn = FALSE))
})

test_that("auto_map refuses the LEPH/EPH edit-distance-1 collision by default (RC6)", {
  ct <- list(cf_field("leph_c10_c19", "numeric"))
  cols <- c("EPH_C10_C19", "LEPH_C10_C19_less_PAH")
  # distance 1 to the WRONG column, distance 9 to the right one
  expect_true(is.na(auto_map(cols, ct)$leph_c10_c19))
  expect_warning(bad <- auto_map(cols, ct, max_distance = 2L), "fuzzy edit distance")
  expect_equal(bad$leph_c10_c19, "EPH_C10_C19")   # exactly the hazard, now opt-in + loud
})

test_that("auto_map warns when an exact name outranks a matching synonym (RC6)", {
  # the "Analyte column holds a matrix label" trap
  ct <- list(cf_field("analyte", "character", TRUE, synonyms = c("parameter")))
  cols <- c("Analyte", "parameter")
  expect_warning(m <- auto_map(cols, ct), "ambiguous mapping")
  expect_equal(m$analyte, "Analyte")            # behaviour unchanged; now announced
  expect_silent(auto_map(c("parameter"), ct))   # no ambiguity, no warning
})

test_that("auto_map uses each source column at most once", {
  cols <- c("site", "site_id")                  # both could match `site`
  expect_warning(m <- auto_map(cols, test_contract()), "ambiguous mapping")
  used <- unlist(m[!is.na(m)])
  expect_equal(length(used), length(unique(used)))
  expect_equal(m$site, "site")                  # the exactly-named column wins
})

test_that("apply_column_map reports values destroyed by coercion (RC5)", {
  df <- data.frame(result = c("1.2", "<0.25", "ND", ">2420"), stringsAsFactors = FALSE)
  ct <- list(cf_field("result", "numeric", TRUE))
  expect_error(apply_column_map(df, list(result = "result"), ct),
               "coercion discarded non-missing values")
  expect_warning(out <- apply_column_map(df, list(result = "result"), ct, loss = "warn"),
                 "coercion discarded non-missing values")
  expect_warning(apply_column_map(df, list(result = "result"), ct, loss = "warn"),
                 "3 of 4 non-missing values")
  expect_equal(out$result, c(1.2, NA, NA, NA))
  expect_warning(apply_column_map(df, list(result = "result"), ct,
                                  warn_coercion = FALSE), "deprecated")
  # and no warning when nothing is lost
  ok <- data.frame(result = c("1.2", "3.4"), stringsAsFactors = FALSE)
  expect_silent(apply_column_map(ok, list(result = "result"), ct))
})

test_that("contracts reject duplicate and malformed field definitions", {
  expect_error(as_contract(list(cf_field("site"), cf_field("site"))), "duplicate")
  expect_error(as_contract(list(list(name = "x"))), "malformed")
})

test_that("strict integer, date, datetime, and time types share one registry", {
  ct <- as_contract(list(
    cf_field("count", "integer", TRUE),
    cf_field("day", "date", TRUE, formats = "%Y-%m-%d"),
    cf_field("stamp", "datetime", TRUE, formats = "%Y-%m-%d %H:%M", tz = "UTC"),
    cf_field("clock", "time", TRUE, formats = "%H:%M")
  ))
  raw <- data.frame(count = c("2", "2.5"), day = c("2026-01-02", "bad"),
                    stamp = c("2026-01-02 03:04", "bad"), clock = c("03:04", "bad"))
  expect_error(suppressWarnings(apply_column_map(
                 raw, as.list(stats::setNames(names(raw), names(raw))), ct)),
               "coercion discarded")
  out <- suppressWarnings(apply_column_map(
    raw, as.list(stats::setNames(names(raw), names(raw))), ct, loss = "allow"))
  expect_equal(out$count, c(2L, NA_integer_))
  expect_s3_class(out$day, "Date")
  expect_s3_class(out$stamp, "POSIXct")
  expect_s3_class(out$clock, "hms")
})

test_that("strict readiness requires rows and valid required values", {
  empty <- tibble::tibble(year = integer(), site = character(), species = character(),
                          length_mm = numeric())
  expect_false(contract_is_ready(empty, test_contract()))
  bad <- tibble::tibble(year = 2024.5, site = "A", species = "RB", length_mm = 10)
  expect_false(contract_is_ready(bad, test_contract()))
  expect_true(contract_is_ready(bad, test_contract(), policy = "structure"))
})

test_that("validation counts use populated values as the invalid denominator", {
  ct <- as_contract(list(cf_field("value", "numeric", TRUE)))
  x <- tibble::tibble(value = c(NA, NA, "1", "bad"))
  v <- validate_against_contract(x, ct, max_invalid_fraction = 0.4)
  expect_equal(v$populated, 2L)
  expect_equal(v$invalid, 1L)
  expect_equal(v$invalid_fraction, 0.5)
  expect_equal(v$severity, "error")
})

test_that("apply_column_map renames, selects, and coerces to declared types", {
  df <- data.frame(Year = "2024", Station = "DC-5", Species = "RB",
                   `Fork Length` = "80.5", check.names = FALSE)
  out <- apply_column_map(df, auto_map(names(df), test_contract()), test_contract())
  expect_equal(names(out), c("year", "site", "species", "length_mm"))
  expect_type(out$year, "integer")
  expect_equal(out$year, 2024L)
  expect_equal(out$length_mm, 80.5)
})

test_that("validate_against_contract flags missing required and all-NA", {
  df <- tibble::tibble(year = 2024L, site = "DC-5", species = "RB")  # length_mm missing
  v <- validate_against_contract(df, test_contract())
  lm <- v[v$field == "length_mm", ]
  expect_equal(lm$status, "missing")
  expect_equal(lm$severity, "error")            # required + missing
  wg <- v[v$field == "weight_g", ]
  expect_equal(wg$severity, "ok")               # optional + missing is ok
})

test_that("complete_to_contract adds typed NA columns; contract_is_ready summarises", {
  df <- tibble::tibble(year = 2024L, site = "DC-5", species = "RB", length_mm = 80)
  full <- complete_to_contract(df, test_contract())
  expect_true("weight_g" %in% names(full))
  expect_true(is.numeric(full$weight_g) && all(is.na(full$weight_g)))
  expect_true(contract_is_ready(df, test_contract()))          # all required present
  expect_false(contract_is_ready(df[, c("year", "site")], test_contract()))
})
