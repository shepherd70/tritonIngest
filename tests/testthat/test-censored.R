test_that("parse_censored handles <DL, tokens, plain numbers, and junk", {
  p <- parse_censored(c("<0.01", "ND", "12.3", "", "junk"))
  expect_equal(p$censored, c(TRUE, TRUE, FALSE, NA, NA))
  expect_equal(p$value,    c(NA, NA, 12.3, NA, NA))
  expect_equal(p$detection_limit[1], 0.01)
  expect_match(p$parse_note[2], "without a detection limit")
  expect_match(p$parse_note[5], "unparseable")
  expect_equal(p$censor_direction, c("left", "left", "none", NA, NA))
})

test_that("parse_censored uses a supplied DL column for tokens and flags disagreement", {
  p <- parse_censored(c("ND", "<0.01"), detection_limit = c(0.05, 0.02))
  expect_equal(p$detection_limit[1], 0.05)         # token takes DL from column
  expect_equal(p$detection_limit[2], 0.01)         # "<0.01" text wins
  expect_match(p$parse_note[2], "differs from detection-limit column")
})

test_that("parse_censored rejects a detection_limit of the wrong length", {
  expect_error(
    parse_censored(c("<0.01", "ND", "5"), detection_limit = c(0.01, 0.02)),
    "must be 1 or match")
  expect_silent(parse_censored(c("ND", "ND"), detection_limit = 0.05))  # length 1 recycles
})

# --- RC4: right-censoring --------------------------------------------------

test_that("parse_censored recognises right-censored values (RC4)", {
  p <- parse_censored(c(">2420", "> 80", "TNTC", "12.3"))
  expect_equal(p$censored,         c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(p$censor_direction, c("right", "right", "right", "none"))
  # the ceiling lives in censor_limit; detection_limit stays NA for ">x"
  expect_equal(p$censor_limit,     c(2420, 80, NA, NA))
  expect_true(all(is.na(p$detection_limit)))
  expect_true(all(is.na(p$value[1:3])))
  expect_match(p$parse_note[3], "over-range token")
  # before 0.6.0 every one of these was "unparseable result text"
  expect_false(any(grepl("unparseable", p$parse_note[1:2])))
})

test_that("a supplied DL column never becomes a right-censored ceiling", {
  p <- parse_censored(c(">2420", "TNTC"), detection_limit = c(1, 1))
  expect_true(all(is.na(p$detection_limit)))   # a ">x" result has no DL
  expect_equal(p$censor_limit, c(2420, NA))
})

test_that("bare right-censor tokens use only the explicit censor limit", {
  p <- parse_censored(c("TNTC", ">80"), censor_limit = c(500, 100))
  expect_equal(p$censor_limit, c(500, 80))
  expect_match(p$parse_note[2], "differs from censor-limit column")
  expect_error(parse_censored(c("TNTC", "TNTC"), censor_limit = c(1, 2, 3)),
               "must be 1 or match")
  expect_error(parse_censored("TNTC", censor_limit = -1), "non-negative")
})

test_that("direction-blind substitution DROPS right-censored values, never halves them", {
  # regression: putting the ceiling in detection_limit made an un-updated caller
  # substitute 0.5 * 2420 = 1210 -- a fabricated number BELOW the true value.
  p <- parse_censored(c("<3.0", ">2420", "5"))
  blind <- apply_substitution(p$value, p$censored, p$detection_limit, 0.5)
  expect_equal(blind, c(1.5, NA, 5))
  expect_true(is.na(blind[2]))

  # direction-aware, done properly
  aware <- apply_substitution(p$value, p$censored, p$detection_limit, 0.5,
                              censor_direction = p$censor_direction,
                              censor_limit = p$censor_limit)
  expect_equal(aware, c(1.5, 2420, 5))

  # naming a right-censored value without giving its bound is an error, not a guess
  expect_error(
    apply_substitution(p$value, p$censored, p$detection_limit, 0.5,
                       censor_direction = p$censor_direction),
    "`censor_limit` was not supplied")

  expect_error(
    apply_substitution(p$value, p$censored, p$detection_limit, 0.5,
                       censor_direction = "left"),
    "`censor_direction` length")
})

test_that("working_values() accepts the parse_censored tibble directly", {
  p <- parse_censored(c("<3.0", ">2420", "5", "ND"))
  expect_equal(working_values(p, fraction = 0.5), c(1.5, 2420, 5, NA))
  expect_equal(working_values(p, fraction = 1),   c(3.0, 2420, 5, NA))
  expect_error(working_values(data.frame(a = 1)), "must be a parse_censored\\(\\) result")
  # and a first-element-NA column is not collapsed by the NA-coalescing %||%
  expect_length(working_values(p), 4)
})

# --- RC4: the "<DL" regex used to accept non-numbers ------------------------

test_that("a censor operator with no number is unparseable, not a clean non-detect", {
  p <- parse_censored(c("<-", "<.", "<e", "<+-", ">"))
  expect_true(all(is.na(p$censored)))              # was TRUE, with an NA limit
  expect_true(all(grepl("unparseable", p$parse_note)))
})

# --- RC4: missing markers and qualifier flags -------------------------------

test_that("na_strings mark a cell missing rather than unparseable", {
  p <- parse_censored(c("-", "n/a", "5"))
  expect_equal(p$parse_note[1:2], c("missing", "missing"))
  expect_true(all(is.na(p$censored[1:2])))
  # opt out
  p2 <- parse_censored("-", na_strings = character(0))
  expect_match(p2$parse_note, "unparseable")
})

test_that("laboratory qualifier flags are separated from the number they decorate", {
  p <- parse_censored(c("178d", "0.06b", "143 a", "114c,RRR", "4.5 RRR",
                        ">45.5c", ">2420a", "<10 DLCI", "MBEF <1", "DTC 0.00842",
                        "1.55 ----"))
  expect_equal(p$value, c(178, 0.06, 143, 114, 4.5, NA, NA, NA, NA, 0.00842, 1.55))
  expect_equal(p$qualifier,
               c("d", "b", "a", "c,RRR", "RRR", "c", "a", "DLCI", "MBEF", "DTC", "----"))
  expect_equal(p$censor_direction[6:9], c("right", "right", "left", "left"))
  expect_equal(p$censor_limit[6:9], c(45.5, 2420, 10, 1))
  expect_equal(p$detection_limit[6:9], c(NA, NA, 10, 1))   # ">x" has no DL

  # qualifiers = FALSE restores the strict reading
  strict <- parse_censored("178d", qualifiers = FALSE)
  expect_true(is.na(strict$censored))
  expect_match(strict$parse_note, "unparseable")
})

test_that("narrative and range cells stay unparseable (no partial-number rescue)", {
  # "5.4 to 8.7" must NOT become the number 5.4 with "to 8.7" as a qualifier
  p <- parse_censored(c("5.4 to 8.7", "50% survival", "100% survival",
                        "Permit limit", "DLA", "VA24C1052"))
  expect_true(all(is.na(p$value)))
  expect_true(all(grepl("unparseable", p$parse_note)))
})

test_that("scientific notation and float artefacts parse as plain numbers", {
  p <- parse_censored(c("7.6E-3", "4.0000000000000001E-3", "-0.2"))
  expect_equal(p$value, c(0.0076, 0.004, -0.2))
  expect_equal(p$censored, c(FALSE, FALSE, FALSE))
})

test_that("apply_substitution replaces censored with fraction*DL", {
  v  <- c(NA, 5)
  cn <- c(TRUE, FALSE)
  dl <- c(0.01, NA)
  expect_equal(apply_substitution(v, cn, dl, fraction = 0.5), c(0.005, 5))
  expect_equal(apply_substitution(v, cn, dl, fraction = 0),   c(0, 5))
  expect_error(apply_substitution(v, cn, dl, fraction = 0.25), "fraction must be")
})

test_that("apply_substitution validates vector lengths", {
  expect_error(apply_substitution(c(NA, 5), TRUE, c(0.01, NA)), "`censored` length")
  expect_error(apply_substitution(c(NA, 5), c(TRUE, FALSE), c(0.01, 0.02, 0.03)),
               "`detection_limit` length")
  # a length-1 detection_limit recycles over the value vector
  expect_equal(apply_substitution(c(NA, NA), c(TRUE, TRUE), 0.02), c(0.01, 0.01))
})

test_that("working_values switches on method", {
  expect_equal(
    working_values(c(NA, 2), c(TRUE, FALSE), c(0.4, NA), method = "substitution"),
    c(0.2, 2))
})
