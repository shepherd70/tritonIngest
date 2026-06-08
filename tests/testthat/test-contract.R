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

test_that("auto_map matches by exact name, synonym, and fuzzy distance", {
  cols <- c("Year", "Station", "Speces", "Fork Length")  # 'Speces' = typo of species
  m <- auto_map(cols, test_contract())
  expect_equal(m$year, "Year")                  # exact (normalised)
  expect_equal(m$site, "Station")               # synonym
  expect_equal(m$species, "Speces")             # fuzzy fallback (edit distance 1)
  expect_equal(m$length_mm, "Fork Length")      # synonym (fork_length)
  expect_true(is.na(m$weight_g))                # nothing left within the fuzzy budget
})

test_that("auto_map uses each source column at most once", {
  cols <- c("site", "site_id")                  # both could match `site`
  m <- auto_map(cols, test_contract())
  used <- unlist(m[!is.na(m)])
  expect_equal(length(used), length(unique(used)))
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
