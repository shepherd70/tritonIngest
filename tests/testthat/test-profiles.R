test_that("mapping_profiles_dir requires a directory", {
  old <- getOption("tritonIngest.profiles_dir")
  options(tritonIngest.profiles_dir = NULL)
  on.exit(options(tritonIngest.profiles_dir = old), add = TRUE)
  expect_error(mapping_profiles_dir(), "No profiles directory")
})

test_that("save/load/list/delete round-trips a profile", {
  dir <- file.path(tempdir(), paste0("mp_", as.integer(Sys.time())))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  maps <- list(catch = list(year = "Yr", site = "Station", length_mm = "Fork Length"))
  path <- save_mapping_profile("2025 master", mappings = maps,
                               meta = list(catch = list(kind = "excel", sheet = "Fish")),
                               dir = dir)
  expect_true(file.exists(path))

  lst <- list_mapping_profiles(dir = dir)
  expect_equal(nrow(lst), 1L)
  expect_equal(lst$name, "2025 master")

  loaded <- load_mapping_profile("2025 master", dir = dir)
  expect_equal(loaded$name, "2025 master")
  # mapping comes back as a named character vector (field -> source column)
  expect_equal(loaded$mappings$catch[["year"]], "Yr")
  expect_equal(loaded$mappings$catch[["length_mm"]], "Fork Length")
  expect_equal(loaded$meta$catch$sheet, "Fish")

  expect_true(delete_mapping_profile("2025 master", dir = dir))
  expect_false(delete_mapping_profile("2025 master", dir = dir))  # already gone
  expect_equal(nrow(list_mapping_profiles(dir = dir)), 0L)
})

test_that("the profiles dir can come from a package option", {
  dir <- file.path(tempdir(), paste0("mp_opt_", as.integer(Sys.time())))
  old <- getOption("tritonIngest.profiles_dir")
  options(tritonIngest.profiles_dir = dir)
  on.exit({ options(tritonIngest.profiles_dir = old); unlink(dir, recursive = TRUE) }, add = TRUE)

  save_mapping_profile("opt", mappings = list(r = list(a = "A")))
  expect_equal(list_mapping_profiles()$name, "opt")
})

test_that("save_mapping_profile errors on a slug collision with a different name", {
  dir <- file.path(tempdir(), paste0("mp_col_", as.integer(Sys.time())))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  save_mapping_profile("2025 master", mappings = list(r = list(a = "A")), dir = dir)
  # "2025_master" sanitises to the same "2025-master.json"
  expect_error(
    save_mapping_profile("2025_master", mappings = list(r = list(b = "B")), dir = dir),
    "collides with existing profile")
  # re-saving the SAME name is a normal overwrite, not a collision
  expect_silent(
    save_mapping_profile("2025 master", mappings = list(r = list(a = "A2")), dir = dir))
})
