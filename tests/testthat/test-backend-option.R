test_that("faissR backend precedence is explicit, option, environment, CPU", {
  old_option <- getOption("faissR.backend", NULL)
  old_env <- Sys.getenv("FAISSR_BACKEND", unset = NA_character_)
  on.exit({
    options(faissR.backend = old_option)
    if (is.na(old_env)) Sys.unsetenv("FAISSR_BACKEND") else Sys.setenv(FAISSR_BACKEND = old_env)
  }, add = TRUE)
  options(faissR.backend = NULL); Sys.unsetenv("FAISSR_BACKEND")
  expect_identical(faissR_backend(), "cpu")
  Sys.setenv(FAISSR_BACKEND = "cuda"); expect_identical(faissR_backend(), "cuda")
  options(faissR.backend = "cpu"); expect_identical(faissR_backend(), "cpu")
  expect_identical(faissR:::resolve_faissr_environment_backend("auto"), "auto")
  expect_identical(faissR:::resolve_faissr_environment_backend("cuda"), "cuda")
  expect_error(faissR:::resolve_faissr_environment_backend("metal"), "does not currently provide")
})

test_that("principal public functions defer omitted backends", {
  functions <- list(nn, candidate_knn, knn, fast_kmeans)
  expect_true(all(vapply(functions, function(fn) is.null(formals(fn)$backend), logical(1))))
  expect_null(formals(getS3method("predict", "faissR_knn_model"))$backend)
})
