test_that("seeded helpers preserve the caller RNG state", {
  set.seed(913)
  before <- .Random.seed

  value <- faissR:::with_rng_seed(7L, stats::runif(4L))

  expect_length(value, 4L)
  expect_identical(.Random.seed, before)
})

test_that("seeded helpers do not create a lasting RNG state", {
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  } else {
    NULL
  }
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)

  if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    rm(".Random.seed", envir = .GlobalEnv)
  }
  faissR:::with_rng_seed(11L, stats::runif(2L))

  expect_false(exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
})
