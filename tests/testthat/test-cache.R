# Tests for the materialisation cache (cache.R).

# Each test gets an isolated dir (session-lived; cleaned with the R tempdir) +
# a small CSV source.
setup_src <- function(rows = 3) {
  d <- tempfile("cache-test-")
  dir.create(d)
  src <- file.path(d, "lab_export.csv")
  utils::write.csv(
    data.frame(site = letters[seq_len(rows)], value = seq_len(rows)),
    src, row.names = FALSE)
  list(dir = file.path(d, "cache"), src = src)
}

test_that("write_cache then read_cache round-trips an object (rds)", {
  s <- setup_src()
  x <- read_tabular(s$src)
  write_cache(x, source = s$src, dir = s$dir, format = "rds")
  got <- read_cache(source = s$src, dir = s$dir, format = "rds")
  expect_equal(got, x)
})

test_that("rds preserves classes/attributes exactly", {
  s <- setup_src()
  x <- structure(tibble::tibble(a = 1:2), class = c("wqlike", "tbl_df", "tbl", "data.frame"),
                 group_vars = "site")
  write_cache(x, source = s$src, key = "obj", dir = s$dir)
  got <- read_cache(key = "obj", source = s$src, dir = s$dir)
  expect_s3_class(got, "wqlike")
  expect_equal(attr(got, "group_vars"), "site")
})

test_that("read_cache returns NULL when the source changed (stale)", {
  s <- setup_src()
  x <- read_tabular(s$src)
  write_cache(x, source = s$src, dir = s$dir)
  expect_false(is.null(read_cache(source = s$src, dir = s$dir)))   # fresh

  Sys.sleep(0.01)
  cat("site,value\nz,99\n", file = s$src)                          # mutate source
  expect_message(res <- read_cache(source = s$src, dir = s$dir), "stale")
  expect_null(res)
})

test_that("read_cache returns NULL on a miss", {
  s <- setup_src()
  expect_null(read_cache(key = "never-written", dir = s$dir, format = "rds"))
})

test_that("cached_ingest parses once, then serves from cache", {
  s <- setup_src()
  calls <- 0
  parse <- function(src) { calls <<- calls + 1; read_tabular(src) }

  a <- cached_ingest(s$src, parse = parse, dir = s$dir)
  b <- cached_ingest(s$src, parse = parse, dir = s$dir)
  expect_equal(a, b)
  expect_equal(calls, 1)                                           # second call hit cache

  Sys.sleep(0.01)
  cat("site,value\nz,99\n", file = s$src)                          # change source
  suppressMessages(cached_ingest(s$src, parse = parse, dir = s$dir))
  expect_equal(calls, 2)                                           # re-parsed on staleness
})

test_that("size_mtime fingerprint also detects a changed source", {
  s <- setup_src()
  x <- read_tabular(s$src)
  write_cache(x, source = s$src, dir = s$dir, fingerprint = "size_mtime")
  expect_false(is.null(read_cache(source = s$src, dir = s$dir)))

  Sys.sleep(0.01)
  cat("site,value\na,1\nb,2\nc,3\nd,4\n", file = s$src)            # size changes
  expect_null(suppressMessages(read_cache(source = s$src, dir = s$dir)))
})

test_that("cache_dir errors when no directory is configured", {
  expect_error(cache_dir(dir = NULL), "cache directory")
})

test_that("parquet backend round-trips a plain table when arrow is available", {
  skip_if_not_installed("arrow")
  s <- setup_src()
  x <- read_tabular(s$src)
  write_cache(x, source = s$src, dir = s$dir, format = "parquet")
  got <- read_cache(source = s$src, dir = s$dir, format = "parquet")
  expect_s3_class(got, "tbl_df")
  expect_equal(as.data.frame(got), as.data.frame(x))
})

test_that("parquet warns that it drops a classed object's attributes", {
  skip_if_not_installed("arrow")
  s <- setup_src()
  x <- structure(tibble::tibble(a = 1:2),
                 class = c("wqlike", "tbl_df", "tbl", "data.frame"))
  expect_warning(write_cache(x, key = "p", dir = s$dir, format = "parquet"),
                 "plain table")
})

test_that("parquet refuses a non-data-frame object", {
  s <- setup_src()
  expect_error(write_cache(list(1, 2), key = "k", dir = s$dir, format = "parquet"),
               "data frame")
})
