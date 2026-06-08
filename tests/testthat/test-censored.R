test_that("parse_censored handles <DL, tokens, plain numbers, and junk", {
  p <- parse_censored(c("<0.01", "ND", "12.3", "", "junk"))
  expect_equal(p$censored, c(TRUE, TRUE, FALSE, NA, NA))
  expect_equal(p$value,    c(NA, NA, 12.3, NA, NA))
  expect_equal(p$detection_limit[1], 0.01)
  expect_match(p$parse_note[2], "without a detection limit")
  expect_match(p$parse_note[5], "unparseable")
})

test_that("parse_censored uses a supplied DL column for tokens and flags disagreement", {
  p <- parse_censored(c("ND", "<0.01"), detection_limit = c(0.05, 0.02))
  expect_equal(p$detection_limit[1], 0.05)         # token takes DL from column
  expect_equal(p$detection_limit[2], 0.01)         # "<0.01" text wins
  expect_match(p$parse_note[2], "differs from detection-limit column")
})

test_that("apply_substitution replaces censored with fraction*DL", {
  v  <- c(NA, 5)
  cn <- c(TRUE, FALSE)
  dl <- c(0.01, NA)
  expect_equal(apply_substitution(v, cn, dl, fraction = 0.5), c(0.005, 5))
  expect_equal(apply_substitution(v, cn, dl, fraction = 0),   c(0, 5))
  expect_error(apply_substitution(v, cn, dl, fraction = 0.25), "fraction must be")
})

test_that("working_values switches on method", {
  expect_equal(
    working_values(c(NA, 2), c(TRUE, FALSE), c(0.4, NA), method = "substitution"),
    c(0.2, 2))
})
